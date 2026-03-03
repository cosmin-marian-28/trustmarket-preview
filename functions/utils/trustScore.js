const { supabase } = require('../config/supabase');

/**
 * Trust Score Management System
 * All trust score operations now use Supabase
 */
class TrustScoreManager {
  constructor() {}

  async _updateTrustScore(userId, points, historyEntry) {
    const { data: user } = await supabase
      .from('users')
      .select('trust_score, trust_points_earned')
      .eq('id', userId)
      .maybeSingle();
    if (!user) throw new Error('User not found');

    const updates = { trust_score: (user.trust_score || 0) + points };
    if (points > 0) updates.trust_points_earned = (user.trust_points_earned || 0) + points;
    await supabase.from('users').update(updates).eq('id', userId);
    await supabase.from('trust_history').insert({ user_id: userId, ...historyEntry, points, created_at: new Date().toISOString() });
  }

  async awardOrderCompletionPoints(buyerId, sellerId, orderId, points = 5) {
    await this._updateTrustScore(buyerId, points, { type: 'order_completed', order_id: orderId, description: 'Order completed successfully' });
    await this._updateTrustScore(sellerId, points, { type: 'order_completed', order_id: orderId, description: 'Order completed successfully' });
    return { success: true, points };
  }

  async deductDisputePoints(sellerId, disputeId, reason, points = 10) {
    await this._updateTrustScore(sellerId, -points, { type: 'dispute_loss', dispute_id: disputeId, reason, description: `Dispute lost - ${reason}` });
    return { success: true, points: -points };
  }

  async deductReturnPoints(sellerId, orderId, points = 10) {
    await this._updateTrustScore(sellerId, -points, { type: 'return_processed', order_id: orderId, description: 'Return processed' });
    return { success: true, points: -points };
  }

  async awardServiceCompletionPoints(buyerId, sellerId, serviceId, points = 5) {
    await this._updateTrustScore(buyerId, points, { type: 'service_completed', service_id: serviceId, description: 'Service completed' });
    await this._updateTrustScore(sellerId, points, { type: 'service_completed', service_id: serviceId, description: 'Service completed' });
    return { success: true, points };
  }

  async deductIncompleteServicePoints(sellerId, serviceId, points = 10) {
    await this._updateTrustScore(sellerId, -points, { type: 'service_incomplete', service_id: serviceId, description: 'Service incomplete' });
    return { success: true, points: -points };
  }

  async deductBadLanguagePoints(userId, conversationId, points = 5) {
    await this._updateTrustScore(userId, -points, { type: 'bad_language_detected', conversation_id: conversationId, description: 'Bad language in chat' });
    return { success: true, points: -points };
  }

  async deductImagePolicyViolationPoints(userId, imageReportId, violation, points = 10) {
    await this._updateTrustScore(userId, -points, { type: 'image_policy_violation', image_report_id: imageReportId, violation, description: `Image violation: ${violation}` });
    return { success: true, points: -points };
  }

  async trackFraudulentProductAttempt(sellerId, attemptNumber, points = 10) {
    if (attemptNumber === 3) {
      await this._updateTrustScore(sellerId, -points, { type: 'fraudulent_product_attempts', description: '3 fraudulent attempts' });
    }
    return { success: true, pointsDeducted: attemptNumber === 3, points: attemptNumber === 3 ? -points : 0 };
  }

  async awardImageVerificationPoints(userId, imageId, points = 15) {
    await this._updateTrustScore(userId, points, { type: 'image_verified', image_id: imageId, description: 'Image verified' });
    return { success: true, points };
  }

  async removeImageVerificationPoints(userId, imageId, points = 15) {
    await this._updateTrustScore(userId, -points, { type: 'image_changed', image_id: imageId, description: 'Image changed' });
    return { success: true, points: -points };
  }

  async restoreImageVerificationPoints(userId, imageId, points = 15) {
    await this._updateTrustScore(userId, points, { type: 'image_re_verified', image_id: imageId, description: 'Image re-verified' });
    return { success: true, points };
  }

  async getUserTrustData(userId) {
    const { data: user } = await supabase.from('users').select('trust_score, trust_points_earned').eq('id', userId).maybeSingle();
    if (!user) throw new Error('User not found');
    const { data: history } = await supabase.from('trust_history').select('*').eq('user_id', userId).order('created_at', { ascending: false }).limit(50);
    return { trustScore: user.trust_score || 0, trustPointsEarned: user.trust_points_earned || 0, history: history || [] };
  }
}

module.exports = TrustScoreManager;
