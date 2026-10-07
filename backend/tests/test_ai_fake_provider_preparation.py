import asyncio
import json
from copy import deepcopy
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import pytest

from app.ai.provider import AiProvider, ProviderResult
from app.ai.schemas import AiAnalyzeRequest
from app.core.errors import AppError
from app.storage.ai_calls import (
    AiCallRepository,
    AiCallState,
    ReservationKind,
    UnsafeCacheResponseError,
)
from app.storage.database import Database


ROOT = Path(__file__).resolve().parents[2]
REQUEST = ROOT / "shared/fixtures/ai/day5-school-model-request.json"
REPORT = ROOT / "shared/fixtures/ai/day5-school-model-mock-report.json"
NOW = datetime(2026, 10, 7, 9, 0, tzinfo=UTC)


@dataclass(frozen=True)
class FakeFailure:
    code: str
    outcome_unknown: bool = False


class ScriptedFakeProvider(AiProvider):
    """Test-only Provider with call counting and an optional concurrency gate."""

    def __init__(
        self,
        *,
        result: ProviderResult | None = None,
        failure: FakeFailure | None = None,
        blocked: bool = False,
    ) -> None:
        self.result = result or provider_result()
        self.failure = failure
        self.calls: list[dict[str, object]] = []
        self.started = asyncio.Event()
        self.release = asyncio.Event()
        if not blocked:
            self.release.set()

    async def analyze(self, payload: dict[str, object]) -> ProviderResult:
        self.calls.append(deepcopy(payload))
        self.started.set()
        await self.release.wait()
        if self.failure is not None:
            raise AppError(
                code=self.failure.code,
                message="fake provider failure",
                status_code=504 if self.failure.outcome_unknown else 503,
                retryable=False,
            )
        return self.result


async def exercise_attempt(
    repository: AiCallRepository,
    provider: ScriptedFakeProvider,
    *,
    user_id,
    analysis_id,
    body,
):
    reservation = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW,
    )
    if reservation.kind is not ReservationKind.ACQUIRED:
        return reservation
    repository.mark_provider_dispatch_started(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=reservation.record.attempt_id,
        now=NOW,
    )
    try:
        result = await provider.analyze(body)
    except AppError as error:
        return repository.complete_failure(
            user_id=user_id,
            analysis_id=analysis_id,
            attempt_id=reservation.record.attempt_id,
            error_code=error.code,
            outcome_unknown=provider.failure.outcome_unknown
            if provider.failure is not None
            else False,
            now=NOW,
        )
    return repository.complete_guarded_success(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=reservation.record.attempt_id,
        payload=AiAnalyzeRequest.model_validate(body),
        result=result,
        now=NOW,
    )


def test_fake_provider_twenty_concurrent_callers_dispatch_once_for_ten_rounds(tmp_path) -> None:
    async def run_round(index: int) -> None:
        repository, user_id, analysis_id, body = setup_repository(tmp_path / str(index))
        provider = ScriptedFakeProvider(blocked=True)
        tasks = [
            asyncio.create_task(
                exercise_attempt(
                    repository,
                    provider,
                    user_id=user_id,
                    analysis_id=analysis_id,
                    body=body,
                )
            )
            for _ in range(20)
        ]
        await provider.started.wait()
        await asyncio.sleep(0)
        provider.release.set()
        results = await asyncio.gather(*tasks)

        assert len(provider.calls) == 1
        assert sum(
            getattr(result, "kind", None) is ReservationKind.IN_PROGRESS
            for result in results
        ) == 19
        assert sum(
            getattr(result, "state", None) is AiCallState.SUCCEEDED
            for result in results
        ) == 1

    async def run() -> None:
        for index in range(10):
            await run_round(index)

    asyncio.run(run())


def test_fake_provider_success_cache_replay_never_dispatches_again(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    provider = ScriptedFakeProvider()

    first = asyncio.run(
        exercise_attempt(
            repository,
            provider,
            user_id=user_id,
            analysis_id=analysis_id,
            body=body,
        )
    )
    replay = asyncio.run(
        exercise_attempt(
            repository,
            provider,
            user_id=user_id,
            analysis_id=analysis_id,
            body=body,
        )
    )

    assert first.state is AiCallState.SUCCEEDED
    assert replay.kind is ReservationKind.CACHED
    assert len(provider.calls) == 1


@pytest.mark.parametrize(
    ("failure", "expected_state", "expected_replay"),
    [
        (
            FakeFailure("AI_PROVIDER_UNAVAILABLE"),
            AiCallState.FAILED_AFTER_PROVIDER,
            ReservationKind.TERMINAL_FAILURE,
        ),
        (
            FakeFailure("AI_PROVIDER_TIMEOUT", outcome_unknown=True),
            AiCallState.OUTCOME_UNKNOWN,
            ReservationKind.OUTCOME_UNKNOWN,
        ),
    ],
)
def test_fake_provider_failure_and_unknown_outcome_never_redispatch(
    tmp_path, failure, expected_state, expected_replay
) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    provider = ScriptedFakeProvider(failure=failure)

    first = asyncio.run(
        exercise_attempt(
            repository,
            provider,
            user_id=user_id,
            analysis_id=analysis_id,
            body=body,
        )
    )
    replay = asyncio.run(
        exercise_attempt(
            repository,
            provider,
            user_id=user_id,
            analysis_id=analysis_id,
            body=body,
        )
    )

    assert first.state is expected_state
    assert replay.kind is expected_replay
    assert len(provider.calls) == 1


@pytest.mark.parametrize("unsafe_kind", ["wrong_analysis", "usage", "sensitive"])
def test_fake_provider_guard_failures_are_terminal_and_not_cached(
    tmp_path, unsafe_kind
) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    result = provider_result()
    if unsafe_kind == "wrong_analysis":
        result.report["analysis_id"] = str(uuid4())
    elif unsafe_kind == "usage":
        result = ProviderResult(
            report=result.report,
            prompt_tokens=120,
            completion_tokens=80,
            total_tokens=201,
            model=result.model,
        )
    else:
        result.report["summary"] = "Authorization: Bearer fake-sensitive-value"
    provider = ScriptedFakeProvider(result=result)

    with pytest.raises((AppError, ValueError, UnsafeCacheResponseError)):
        asyncio.run(
            exercise_attempt(
                repository,
                provider,
                user_id=user_id,
                analysis_id=analysis_id,
                body=body,
            )
        )

    record = repository.get_for_owner(user_id=user_id, analysis_id=analysis_id)
    replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(seconds=1),
    )
    assert record is not None
    assert record.state is AiCallState.FAILED_AFTER_PROVIDER
    assert record.response is None
    assert replay.kind is ReservationKind.TERMINAL_FAILURE
    assert len(provider.calls) == 1


def setup_repository(path: Path):
    path.mkdir(parents=True, exist_ok=True)
    database = Database(path / "taplens-test.db")
    database.initialize()
    user_id = uuid4()
    with database.connect() as connection:
        connection.execute(
            """
            INSERT INTO users (id, username, username_normalized, password_hash, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                str(user_id),
                f"user-{user_id}",
                f"user-{user_id}",
                "not-a-real-password-hash",
                NOW.isoformat(),
            ),
        )
    repository = AiCallRepository(
        database,
        digest_secrets={1: "day9-fake-provider-secret"},
        active_digest_key_version=1,
    )
    body = json.loads(REQUEST.read_text(encoding="utf-8"))
    return repository, user_id, UUID(body["report_context"]["analysis_id"]), body


def provider_result() -> ProviderResult:
    return ProviderResult(
        report=json.loads(REPORT.read_text(encoding="utf-8")),
        prompt_tokens=120,
        completion_tokens=80,
        total_tokens=200,
        model="cuc/deepseek",
    )
