/**
 * Idempotency Utilities
 * Prevents duplicate operations (payouts, webhooks, etc.)
 */

const { supabase } = require('../config/supabase');

/**
 * Generate idempotency key for payouts
 */
function generatePayoutIdempotencyKey(orderId) {
  const attemptId = `${orderId}-${Date.now()}`;
  const idempotencyKey = `payout-${attemptId}`;
  return { attemptId, idempotencyKey };
}

/**
 * Check if webhook event already processed
 */
async function isWebhookProcessed(eventId) {
  const { data } = await supabase
    .from('processed_webhook_events')
    .select('id')
    .eq('id', eventId)
    .maybeSingle();
  return !!data;
}

/**
 * Mark webhook event as processed
 */
async function markWebhookProcessed(eventId, metadata = {}) {
  await supabase.from('processed_webhook_events').upsert({
    id: eventId,
    ...metadata,
    processed_at: new Date().toISOString()
  });
}

/**
 * Acquire transaction lock for order processing
 * Prevents race conditions in payout/capture operations
 */
async function acquireOrderLock(orderId) {
  try {
    // Read current payout status
    const { data: order } = await supabase
      .from('orders')
      .select('payout')
      .eq('id', orderId)
      .maybeSingle();

    const currentPayoutStatus = order?.payout?.status;

    if (currentPayoutStatus === 'processing' || currentPayoutStatus === 'completed') {
      console.log(`⚠️ [LOCK] Already processing for ${orderId}`);
      return false;
    }

    // Acquire lock
    const existingPayout = order?.payout || {};
    const { error } = await supabase
      .from('orders')
      .update({
        payout: {
          ...existingPayout,
          status: 'processing',
          processingStartedAt: new Date().toISOString()
        },
        updated_at: new Date().toISOString()
      })
      .eq('id', orderId);

    if (error) {
      console.error(`❌ [LOCK] Failed for ${orderId}:`, error.message);
      return false;
    }

    return true;
  } catch (error) {
    console.error(`❌ [LOCK] Failed to acquire lock for ${orderId}:`, error.message);
    return false;
  }
}

module.exports = { generatePayoutIdempotencyKey, isWebhookProcessed, markWebhookProcessed, acquireOrderLock };
