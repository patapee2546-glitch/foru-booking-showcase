import { processNotificationBatch } from './core.ts'

function equal(actual: unknown, expected: unknown, label: string) {
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, got ${actual}`)
}

const jobs = [
  { id:'job-1', booking_id:'booking-1', recipient_line_user_id:'U11111111', notification_type:'booking_confirmed' as const },
  { id:'job-2', booking_id:'booking-2', recipient_line_user_id:'U22222222', notification_type:'appointment_reminder' as const },
  { id:'job-3', booking_id:'booking-3', recipient_line_user_id:'U33333333', notification_type:'appointment_reminder' as const },
]

Deno.test('worker records sent, retryable, and cancelled jobs independently', async () => {
  const finished: Array<Record<string, unknown>> = []
  const cancelled: string[] = []
  const outcomes = new Map([['job-1','sent'], ['job-2','retryable'], ['job-3','cancelled']])
  const result = await processNotificationBatch(jobs, {
    sendJob: async job => outcomes.get(job.id) as 'sent' | 'retryable' | 'cancelled',
    finishJob: async args => { finished.push(args) },
    cancelJob: async id => { cancelled.push(id) },
  })
  equal(result.processed, 3, 'processed jobs')
  equal(result.sent, 1, 'sent jobs')
  equal(result.failed, 1, 'retryable failures')
  equal(finished.length, 2, 'finished updates')
  equal(finished[0].sent, true, 'successful finish')
  equal(finished[1].retryable, true, 'retryable finish')
  equal(cancelled[0], 'job-3', 'cancelled job')
})

Deno.test('one unexpected job error does not stop later jobs', async () => {
  const finished: Array<Record<string, unknown>> = []
  const result = await processNotificationBatch(jobs.slice(0, 2), {
    sendJob: async job => {
      if (job.id === 'job-1') throw new Error('temporary database failure')
      return 'sent'
    },
    finishJob: async args => { finished.push(args) },
    cancelJob: async () => {},
  })
  equal(result.processed, 2, 'both jobs processed')
  equal(result.sent, 1, 'later job sent')
  equal(result.failed, 1, 'unexpected error retried')
  equal(finished[0].retryable, true, 'unexpected error is retryable')
})
