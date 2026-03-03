/**
 * Retry Logic with Exponential Backoff
 * Handles payout retries and DLQ management
 */

const { supabase } = require('../config/supabase');
const { PAYOUT_RETRY } = require('../config/constants');

/**
 * Calculate next retry time with exponential backoff
 */
function calculateNextRetry(retryCount = 0) {
  const nextRetryCount = retryCount + 1;
  const maxRetries = PAYOUT_RETRY.MAX_RETRIES;

  if (nextRetryCount > maxRetries) {
    return { shouldRetry: false, nextRetryCount };
  }

  const delaySeconds = PAYOUT_RETRY.RETRY_DELAYS[Math.min(nextRetryCount - 1, PAYOUT_RETRY.RETRY_DELAYS.length - 1)];
  const nextRetryAt = new Date(Date.now() + delaySeconds * 1000);

  return { shouldRetry: true, nextRetryCount, nextRetryAt, delaySeconds };
}

/**
 * Mark payout for retry with exponential backoff
 * @param {string} orderId - Order ID
 * @param {string} errorMessage - Error message
 * @param {number} currentRetryCount - Current retry count
 * @param {object} existingPayout - Existing payout data from order
 */
async function markForRetry(orderId, errorMessage, currentRetryCount = 0, existingPayout = {}) {
  const retry = calculateNextRetry(currentRetryCount);

  if (retry.shouldRetry) {
    console.log(`🔄 Retry ${retry.nextRetryCount}/${PAYOUT_RETRY.MAX_RETRIES} scheduled for ${retry.nextRetryAt.toISOString()}`);

    await supabase
      .from('orders')
      .update({
        payout: {
          ...existingPayout,
          status: 'failed_retrying',
          reason: errorMessage,
          failedAt: new Date().toISOString(),
          retryCount: retry.nextRetryCount,
          lastRetryAt: new Date().toISOString(),
          nextRetryAt: retry.nextRetryAt.toISOString()
        },
        updated_at: new Date().toISOString()
      })
      .eq('id', orderId);

    return { retrying: true, nextRetryAt: retry.nextRetryAt };
  } else {
    return await moveToDeadLetterQueue(orderId, errorMessage, retry.nextRetryCount, existingPayout);
  }
}

/**
 * Move failed payout to Dead Letter Queue (admin alerts)
 */
async function moveToDeadLetterQueue(orderId, errorMessage, retryCount, existingPayout = {}) {
  console.error(`🚨 Max retries (${PAYOUT_RETRY.MAX_RETRIES}) exceeded for order ${orderId}`);

  const { data: order } = await supabase
    .from('orders')
    .select('*')
    .eq('id', orderId)
    .maybeSingle();

  await supabase
    .from('orders')
    .update({
      payout: {
        ...existingPayout,
        status: 'failed_permanent',
        reason: `Max retries exceeded: ${errorMessage}`,
        failedAt: new Date().toISOString(),
        retryCount: retryCount
      },
      updated_at: new Date().toISOString()
    })
    .eq('id', orderId);

  // Create admin alert
  await supabase.from('admin_alerts').insert({
    type: 'payout_failed_permanent',
    order_id: orderId,
    seller_id: order?.seller_id,
    amount: order?.payment?.basePrice || order?.price,
    currency: order?.currency || 'RON',
    error: errorMessage,
    retry_count: retryCount,
    stripe_account_id: order?.payout?.stripeAccountId,
    created_at: new Date().toISOString(),
    status: 'open',
    priority: 'high'
  });

  console.log(`📩 Admin alert created for manual review`);
  return { retrying: false, movedToDLQ: true };
}

/**
 * Enqueue payout retry job
 */
async function enqueueRetryJob(orderId, sellerId, reason = 'manual_retry') {
  await supabase.from('payout_retry_queue').insert({
    order_id: orderId,
    seller_id: sellerId,
    reason,
    enqueued_at: new Date().toISOString(),
    status: 'pending',
    priority: 'high'
  });

  console.log(`✅ Retry job enqueued for order ${orderId}`);
}

module.exports = { calculateNextRetry, markForRetry, moveToDeadLetterQueue, enqueueRetryJob };
