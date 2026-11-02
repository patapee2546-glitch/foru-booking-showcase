import type { NotificationJob } from '../_shared/line-notification.ts'

type Outcome = 'sent' | 'retryable' | 'permanent' | 'cancelled'
type FinishArgs = { id: string; sent: boolean; error: string | null; retryable: boolean }
type Dependencies = {
  sendJob(job: NotificationJob): Promise<Outcome>
  finishJob(args: FinishArgs): Promise<void>
  cancelJob(id: string): Promise<void>
}

export async function processNotificationBatch(
  jobs: NotificationJob[],
  dependencies: Dependencies,
): Promise<{ processed: number; sent: number; failed: number }> {
  let sent = 0
  let failed = 0
  for (const job of jobs) {
    try {
      const outcome = await dependencies.sendJob(job)
      if (outcome === 'cancelled') {
        await dependencies.cancelJob(job.id)
      } else {
        await dependencies.finishJob({
          id: job.id,
          sent: outcome === 'sent',
          error: outcome === 'sent' ? null : outcome,
          retryable: outcome === 'retryable',
        })
        if (outcome === 'sent') sent += 1
        else failed += 1
      }
    } catch {
      failed += 1
      await dependencies.finishJob({
        id: job.id,
        sent: false,
        error: 'unexpected_error',
        retryable: true,
      })
    }
  }
  return { processed:jobs.length, sent, failed }
}
