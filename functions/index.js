/**
 * Buy:Sell Marketplace - Cloud Functions
 * Main entry point - exports all modular functions
 * 
 * Architecture:
 * - payments/: Payment processing, Stripe Connect, payouts
 * - shipping/: Shipping calculation, tracking, labels, deadlines
 * - products/: Product analysis, AI validation
 * - identity/: Face verification, KYC
 * - admin/: Migration utilities, accounting reports
 * 
 * All business logic has been moved to domain modules.
 * This file only imports and exports.
 */

// Import all modules
const payments = require('./payments');
const shipping = require('./shipping');
const products = require('./products');
const services = require('./services');
const gigs = require('./gigs');
const identity = require('./identity');
const admin = require('./admin');
const notifications = require('./notifications');
const offers = require('./offers');
const health = require('./health');
const siri = require('./siri');
const disputes = require('./disputes');
const chat = require('./chat');
const support = require('./support');
const orders = require('./orders');
const inactivityScheduler = require('./users/inactivityScheduler');
// const { aiProductQuestions } = require('./support/aiProductQuestions');

// Export all functions
module.exports = {
  // ============ PAYMENT FUNCTIONS (18) ============
  // Payment intent creation
  createPaymentIntent: payments.createPaymentIntent,
  createListingFeePayment: payments.createListingFeePayment,
  createInterestFeePayment: payments.createInterestFeePayment,
  
  // Promotion payments
  createPromotionPaymentIntent: payments.createPromotionPaymentIntent,
  confirmPromotionPayment: payments.confirmPromotionPayment,
  expirePromotions: payments.expirePromotions,
  
  // Payment confirmation
  confirmPaymentAuthorization: payments.confirmPaymentAuthorization,
  
  // Payment methods management
  managePaymentMethods: payments.managePaymentMethods,
  
  // Stripe Connect account management
  manageSellerPayoutAccount: payments.manageSellerPayoutAccount,
  upgradeSellerPayoutAccount: payments.upgradeSellerPayoutAccount,
  checkPayoutVerificationStatus: payments.checkPayoutVerificationStatus,
  checkSellerThresholdOnOrderComplete: payments.checkSellerThresholdOnOrderComplete,
  
  // Payout processing
  onOrderStatusChangeToDelivered: payments.onOrderStatusChangeToDelivered,
  getOrderPayoutStatus: payments.getOrderPayoutStatus,
  processPayouts: payments.processPayouts,
  
  // Payment capture (5-hour delay system)
  schedulePaymentCapture: payments.schedulePaymentCapture,
  processPendingCaptures: payments.processPendingCaptures,
  
  // Webhooks
  handleStripeWebhook: payments.handleStripeWebhook,
  stripeWebhookAccountUpdates: payments.stripeWebhookAccountUpdates,
  
  // Disputes management
  manageDisputes: payments.manageDisputes,
  
  // Maintenance
  cleanupProcessedWebhookEvents: payments.cleanupProcessedWebhookEvents,
  
  // ============ SHIPPING FUNCTIONS (4) ============
  // Callable functions
  getTrackingInfo: shipping.getTrackingInfo,
  reportDeliveryProblem: shipping.reportDeliveryProblem,
  estimateShippingCost: shipping.estimateShippingCost,
  
  // HTTP endpoint - Supabase webhook
  createShippingLabelForOrder: shipping.createShippingLabelForOrder,
  
  // Scheduled functions
  enforceShippingDeadlines: shipping.enforceShippingDeadlines,
  
  // Refund expired orders (buyer-triggered)
  refundExpiredOrder: shipping.refundExpiredOrder,
  
  // ============ PRODUCT FUNCTIONS (3) ============
  analyzeProductDescription: products.analyzeProductDescription,
  analyzeProductWithImage: products.analyzeProductWithImage,
  verifyInventory: products.verifyInventory,
  
  // ============ SERVICE FUNCTIONS (4) ============
  analyzeServiceOnCreate: services.analyzeServiceOnCreate,
  analyzeServiceCallable: services.analyzeServiceCallable,
  createServicePurchaseIntent: services.createServicePurchaseIntent,
  createOfflineServiceFeePayment: services.createOfflineServiceFeePayment,
  refundServiceBooking: services.refundServiceBooking,
  
  // ============ GIG FUNCTIONS (1) ============
  analyzeGig: gigs.analyzeGig,
  
  // ============ IDENTITY FUNCTIONS (1) ============
  verifyFaceFromSnapshotsHttp: identity.verifyFaceFromSnapshotsHttp,
  
  // ============ ADMIN FUNCTIONS (2) ============
  migrateToStripeConnect: admin.migrateToStripeConnect,
  getAccountingReport: admin.getAccountingReport,
  
  // ============ NOTIFICATION FUNCTIONS (3) ============
  // HTTP endpoints - called by Supabase DB triggers via pg_net
  onOrderStatusChange: notifications.onOrderStatusChange,
  onNewMessage: notifications.onNewMessage,
  onOfferAccepted: notifications.onOfferAccepted,
  
  // ============ OFFER FUNCTIONS (2) ============
  // Secure offer token management
  generateOfferToken: offers.generateOfferToken,
  validateOfferToken: offers.validateOfferToken,
  
  // ============ SIRI INTEGRATION (2) ============
  siriSearchProducts: siri.siriSearchProducts,
  siriSearchServices: siri.siriSearchServices,
  
  // ============ DISPUTE RESOLUTION (7) ============
  analyzeDisputeWithAI: disputes.analyzeDisputeWithAI,
  onDisputeCreated: disputes.onDisputeCreated,
  resolveDisputeManually: disputes.resolveDisputeManually,
  
  // Return handling
  sellerAcceptsReturn: disputes.sellerAcceptsReturn,
  // TODO: Add these when implemented:
  // buyerRightReturn: disputes.buyerRightReturn,
  // sellerRightReturn: disputes.sellerRightReturn,
  // onReturnDelivered: disputes.onReturnDelivered,
  
  // ============ CHAT FUNCTIONS (2) ============
  analyzeReportedImage: chat.analyzeReportedImage,
  getImageReport: chat.getImageReport,
  
  // ============ SUPPORT FUNCTIONS ============
  handleConversationalFlow: support.handleConversationalFlow,
  
  // Voice Chat (WebSocket server on Cloud Run)
  createVoiceSession: support.createVoiceSession,
  endVoiceSession: support.endVoiceSession,
  
  // ============ HEALTH CHECK ============
  health: health,
  
  // ============ ORDER FUNCTIONS (3) ============
  // Group buy / quantity purchases
  validateQuantityPurchase: orders.validateQuantityPurchase,
  processGroupBuyOrder: orders.processGroupBuyOrder,
  cleanupExpiredQuantityRequests: orders.cleanupExpiredQuantityRequests,
  
  // ============ USER INACTIVITY (1) ============
  deactivateInactiveListings: inactivityScheduler.deactivateInactiveListings,
};
