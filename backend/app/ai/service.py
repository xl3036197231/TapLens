import asyncio
from contextlib import suppress
from datetime import UTC, datetime
from uuid import UUID

from app.ai.provider import AiProvider
from app.ai.schemas import AiAnalyzeRequest, AiAnalyzeResponse
from app.core.errors import AppError
from app.storage.ai_calls import AiCallRepository, ReservationKind


UNKNOWN_PROVIDER_CODES = {"AI_PROVIDER_TIMEOUT"}


class AiAnalysisService:
    def __init__(
        self,
        repository: AiCallRepository,
        provider: AiProvider,
        *,
        clock=None,
    ) -> None:
        self.repository = repository
        self.provider = provider
        self.clock = clock or (lambda: datetime.now(UTC))

    async def analyze(
        self,
        *,
        user_id: UUID,
        payload: AiAnalyzeRequest,
        payload_data: dict[str, object],
    ) -> AiAnalyzeResponse:
        analysis_id = payload.report_context.analysis_id
        reservation = self.repository.reserve(
            user_id=user_id,
            analysis_id=analysis_id,
            payload=payload_data,
            now=self.clock(),
        )
        if reservation.kind is ReservationKind.CACHED:
            if reservation.record.response is None:
                raise RuntimeError("cached AI reservation has no response")
            return AiAnalyzeResponse.model_validate(reservation.record.response)
        if reservation.kind is not ReservationKind.ACQUIRED:
            raise self._reservation_error(reservation.kind, analysis_id)

        attempt_id = reservation.record.attempt_id
        self.repository.mark_provider_dispatch_started(
            user_id=user_id,
            analysis_id=analysis_id,
            attempt_id=attempt_id,
            now=self.clock(),
        )
        try:
            result = await self._analyze_with_lease_renewal(
                user_id=user_id,
                analysis_id=analysis_id,
                attempt_id=attempt_id,
                payload=payload_data,
            )
        except AppError as error:
            outcome_unknown = error.code in UNKNOWN_PROVIDER_CODES
            self.repository.complete_failure(
                user_id=user_id,
                analysis_id=analysis_id,
                attempt_id=attempt_id,
                error_code=("AI_OUTCOME_UNKNOWN" if outcome_unknown else error.code),
                outcome_unknown=outcome_unknown,
                now=self.clock(),
            )
            if outcome_unknown:
                raise self._reservation_error(
                    ReservationKind.OUTCOME_UNKNOWN, analysis_id
                ) from error
            raise AppError(
                code=error.code,
                message=error.message,
                status_code=error.status_code,
                retryable=False,
            ) from error
        except asyncio.CancelledError:
            self.repository.complete_failure(
                user_id=user_id,
                analysis_id=analysis_id,
                attempt_id=attempt_id,
                error_code="AI_OUTCOME_UNKNOWN",
                outcome_unknown=True,
                now=self.clock(),
            )
            raise
        except Exception:
            self.repository.complete_failure(
                user_id=user_id,
                analysis_id=analysis_id,
                attempt_id=attempt_id,
                error_code="AI_OUTCOME_UNKNOWN",
                outcome_unknown=True,
                now=self.clock(),
            )
            raise

        record = self.repository.complete_guarded_success(
            user_id=user_id,
            analysis_id=analysis_id,
            attempt_id=attempt_id,
            payload=payload,
            payload_data=payload_data,
            result=result,
            now=self.clock(),
        )
        if record.response is None:
            raise RuntimeError("guarded AI completion did not cache a response")
        return AiAnalyzeResponse.model_validate(record.response)

    async def _analyze_with_lease_renewal(
        self,
        *,
        user_id: UUID,
        analysis_id: UUID,
        attempt_id: UUID,
        payload: dict[str, object],
    ):
        task = asyncio.create_task(self.provider.analyze(payload))
        interval = max(0.05, self.repository.lease.total_seconds() / 3)
        try:
            while True:
                done, _ = await asyncio.wait({task}, timeout=interval)
                if task in done:
                    return await task
                self.repository.renew_lease(
                    user_id=user_id,
                    analysis_id=analysis_id,
                    attempt_id=attempt_id,
                    now=self.clock(),
                )
        except BaseException:
            if not task.done():
                task.cancel()
            with suppress(BaseException):
                await task
            raise

    @staticmethod
    def _reservation_error(kind: ReservationKind, analysis_id: UUID) -> AppError:
        code, message = {
            ReservationKind.IN_PROGRESS: (
                "AI_REQUEST_IN_PROGRESS",
                "分析仍在进行，请查询状态",
            ),
            ReservationKind.INPUT_CONFLICT: (
                "AI_ANALYSIS_INPUT_CONFLICT",
                "analysis_id 已绑定到不同输入",
            ),
            ReservationKind.OUTCOME_UNKNOWN: (
                "AI_OUTCOME_UNKNOWN",
                "上次分析结果待核实，请查询状态",
            ),
            ReservationKind.RESULT_EXPIRED: (
                "AI_RESULT_EXPIRED",
                "缓存结果已清除，禁止重新调用",
            ),
            ReservationKind.TERMINAL_FAILURE: (
                "AI_ANALYSIS_FAILED",
                "分析已进入稳定失败状态，请查询状态",
            ),
        }[kind]
        return AppError(
            code=code,
            message=message,
            status_code=409,
            retryable=False,
            details={
                "status_path": f"/api/v1/ai/analyses/{analysis_id}/status",
                "poll_after_seconds": 2,
            },
        )
