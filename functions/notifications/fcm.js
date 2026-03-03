const admin = require('firebase-admin');
const { supabase } = require('../config/supabase');

/**
 * Send FCM notification to a user
 * @param {string} userId - User ID to send notification to
 * @param {object} notification - Notification payload
 * @param {string} notification.title - Notification title
 * @param {string} notification.body - Notification body
 * @param {object} notification.data - Optional data payload
 * @returns {Promise<void>}
 */
async function sendNotificationToUser(userId, notification) {
  try {
    console.log(`📱 Sending notification to user ${userId}:`, notification.title);

    // Get user's FCM tokens from Supabase
    const { data: userData, error } = await supabase
      .from('users')
      .select('fcm_tokens')
      .eq('id', userId)
      .single();

    if (error || !userData) {
      console.log(`⚠️ User ${userId} not found`);
      return;
    }

    const fcmTokens = userData.fcm_tokens || [];

    if (fcmTokens.length === 0) {
      console.log(`⚠️ User ${userId} has no FCM tokens`);
      return;
    }

    // Prepare the message
    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: notification.data || {},
      // iOS specific settings
      apns: {
        payload: {
          aps: {
            sound: 'default',
            // Don't set badge here — let the client manage badge count
            // Setting badge: 1 caused a ghost "1" badge that persisted
          },
        },
      },
      // Android specific settings
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'orders',
        },
      },
    };

    // Send to all user's devices
    const results = await Promise.allSettled(
      fcmTokens.map(token => 
        admin.messaging().send({
          ...message,
          token: token,
        })
      )
    );

    // Remove invalid tokens
    const invalidTokens = [];
    results.forEach((result, index) => {
      if (result.status === 'rejected') {
        const error = result.reason;
        if (
          error.code === 'messaging/invalid-registration-token' ||
          error.code === 'messaging/registration-token-not-registered'
        ) {
          invalidTokens.push(fcmTokens[index]);
        }
      }
    });

    // Clean up invalid tokens
    if (invalidTokens.length > 0) {
      console.log(`🧹 Removing ${invalidTokens.length} invalid tokens`);
      
      // Remove invalid tokens from array
      const updatedTokens = fcmTokens.filter(token => !invalidTokens.includes(token));
      
      await supabase
        .from('users')
        .update({ fcm_tokens: updatedTokens })
        .eq('id', userId);
    }

    const successCount = results.filter(r => r.status === 'fulfilled').length;
    console.log(`✅ Sent notification to ${successCount}/${fcmTokens.length} devices`);

  } catch (error) {
    console.error('❌ Error sending notification:', error);
    throw error;
  }
}

/**
 * Send notification to multiple users
 * @param {string[]} userIds - Array of user IDs
 * @param {object} notification - Notification payload
 * @returns {Promise<void>}
 */
async function sendNotificationToUsers(userIds, notification) {
  await Promise.all(
    userIds.map(userId => sendNotificationToUser(userId, notification))
  );
}

module.exports = {
  sendNotificationToUser,
  sendNotificationToUsers,
};
