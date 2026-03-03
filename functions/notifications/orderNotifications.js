const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { sendNotificationToUser } = require('./fcm');

/**
 * Get user's preferred language
 */
async function getUserLanguage(userId) {
  try {
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const userData = userDoc.data();
    // Check both 'preferredLanguage' (used by Flutter app) and 'language' (legacy)
    return userData?.preferredLanguage || userData?.language || 'en';
  } catch (error) {
    console.error('Error getting user language:', error);
    return 'en';
  }
}

/**
 * Notification translations
 * Supports: en, ro, it, fr, es, de
 */
const notifications = {
  payment_captured: {
    title: {
      en: 'Payment Received',
      ro: 'Plată Primită',
      it: 'Pagamento Ricevuto',
      fr: 'Paiement Reçu',
      es: 'Pago Recibido',
      de: 'Zahlung Erhalten',
    },
    body: {
      en: '{amount} {currency} will be sent to your account for {product}',
      ro: '{amount} {currency} vor fi trimise în contul tău pentru {product}',
      it: '{amount} {currency} saranno inviati al tuo account per {product}',
      fr: '{amount} {currency} seront envoyés sur votre compte pour {product}',
      es: '{amount} {currency} se enviarán a tu cuenta por {product}',
      de: '{amount} {currency} werden auf Ihr Konto für {product} überwiesen',
    },
  },
  new_order: {
    title: {
      en: 'New Order',
      ro: 'Comandă Nouă',
      it: 'Nuovo Ordine',
      fr: 'Nouvelle Commande',
      es: 'Nuevo Pedido',
      de: 'Neue Bestellung',
    },
    body: {
      en: '{buyer} ordered {product} for {amount} {currency}',
      ro: '{buyer} a comandat {product} pentru {amount} {currency}',
      it: '{buyer} ha ordinato {product} per {amount} {currency}',
      fr: '{buyer} a commandé {product} pour {amount} {currency}',
      es: '{buyer} pidió {product} por {amount} {currency}',
      de: '{buyer} hat {product} für {amount} {currency} bestellt',
    },
  },
  order_shipped: {
    title: {
      en: 'Package Shipped',
      ro: 'Pachet Expediat',
      it: 'Pacco Spedito',
      fr: 'Colis Expédié',
      es: 'Paquete Enviado',
      de: 'Paket Versendet',
    },
    body: {
      en: '{product} is on its way to you',
      ro: '{product} este în drum spre tine',
      it: '{product} è in viaggio verso di te',
      fr: '{product} est en route vers vous',
      es: '{product} está en camino hacia ti',
      de: '{product} ist auf dem Weg zu Ihnen',
    },
  },
  order_delivered_buyer: {
    title: {
      en: 'Delivered',
      ro: 'Livrat',
      it: 'Consegnato',
      fr: 'Livré',
      es: 'Entregado',
      de: 'Geliefert',
    },
    body: {
      en: '{product} has been delivered',
      ro: '{product} a fost livrat',
      it: '{product} è stato consegnato',
      fr: '{product} a été livré',
      es: '{product} ha sido entregado',
      de: '{product} wurde geliefert',
    },
  },
  order_delivered_seller: {
    title: {
      en: 'Order Delivered',
      ro: 'Comandă Livrată',
      it: 'Ordine Consegnato',
      fr: 'Commande Livrée',
      es: 'Pedido Entregado',
      de: 'Bestellung Geliefert',
    },
    body: {
      en: 'Payout of {amount} {currency} for {product}',
      ro: 'Plată de {amount} {currency} pentru {product}',
      it: 'Pagamento di {amount} {currency} per {product}',
      fr: 'Paiement de {amount} {currency} pour {product}',
      es: 'Pago de {amount} {currency} por {product}',
      de: 'Auszahlung von {amount} {currency} für {product}',
    },
  },
  package_picked_up: {
    title: {
      en: 'Package Picked Up',
      ro: 'Pachet Ridicat',
      it: 'Pacco Ritirato',
      fr: 'Colis Récupéré',
      es: 'Paquete Recogido',
      de: 'Paket Abgeholt',
    },
    body: {
      en: '{carrier} picked up your package. Tracking: {tracking}',
      ro: '{carrier} a ridicat pachetul. Tracking: {tracking}',
      it: '{carrier} ha ritirato il tuo pacco. Tracking: {tracking}',
      fr: '{carrier} a récupéré votre colis. Suivi: {tracking}',
      es: '{carrier} recogió tu paquete. Seguimiento: {tracking}',
      de: '{carrier} hat Ihr Paket abgeholt. Tracking: {tracking}',
    },
  },
  dispute_started: {
    title: {
      en: 'Dispute Started',
      ro: 'Dispută Deschisă',
      it: 'Disputa Aperta',
      fr: 'Litige Ouvert',
      es: 'Disputa Iniciada',
      de: 'Streitfall Eröffnet',
    },
    body: {
      en: '{buyer} started a dispute for {product}',
      ro: '{buyer} a deschis o dispută pentru {product}',
      it: '{buyer} ha aperto una disputa per {product}',
      fr: '{buyer} a ouvert un litige pour {product}',
      es: '{buyer} inició una disputa por {product}',
      de: '{buyer} hat einen Streitfall für {product} eröffnet',
    },
  },
  order_cancelled: {
    title: {
      en: 'Order Cancelled',
      ro: 'Comandă Anulată',
      it: 'Ordine Annullato',
      fr: 'Commande Annulée',
      es: 'Pedido Cancelado',
      de: 'Bestellung Storniert',
    },
    body: {
      en: '{product} has been cancelled',
      ro: '{product} a fost anulată',
      it: '{product} è stato annullato',
      fr: '{product} a été annulée',
      es: '{product} ha sido cancelado',
      de: '{product} wurde storniert',
    },
  },
  order_returned: {
    title: {
      en: 'Order Returned',
      ro: 'Comandă Returnată',
      it: 'Ordine Restituito',
      fr: 'Commande Retournée',
      es: 'Pedido Devuelto',
      de: 'Bestellung Zurückgegeben',
    },
    body: {
      en: '{product} has been returned',
      ro: '{product} a fost returnat',
      it: '{product} è stato restituito',
      fr: '{product} a été retourné',
      es: '{product} ha sido devuelto',
      de: '{product} wurde zurückgegeben',
    },
  },
  offer_accepted: {
    title: {
      en: 'Offer Accepted',
      ro: 'Ofertă Acceptată',
      it: 'Offerta Accettata',
      fr: 'Offre Acceptée',
      es: 'Oferta Aceptada',
      de: 'Angebot Angenommen',
    },
    body: {
      en: 'Your offer of {amount} {currency} for {product} was accepted',
      ro: 'Oferta ta de {amount} {currency} pentru {product} a fost acceptată',
      it: 'La tua offerta di {amount} {currency} per {product} è stata accettata',
      fr: 'Votre offre de {amount} {currency} pour {product} a été acceptée',
      es: 'Tu oferta de {amount} {currency} por {product} fue aceptada',
      de: 'Ihr Angebot von {amount} {currency} für {product} wurde angenommen',
    },
  },
  boost_ended: {
    title: {
      en: 'Boost Ended',
      ro: 'Promovare Încheiată',
      it: 'Promozione Terminata',
      fr: 'Promotion Terminée',
      es: 'Promoción Finalizada',
      de: 'Werbung Beendet',
    },
    body: {
      en: 'Your boost for {product} has ended',
      ro: 'Promovarea pentru {product} s-a încheiat',
      it: 'La tua promozione per {product} è terminata',
      fr: 'Votre promotion pour {product} est terminée',
      es: 'Tu promoción para {product} ha finalizado',
      de: 'Ihre Werbung für {product} ist beendet',
    },
  },
};

/**
 * Get translated notification
 */
function getNotification(key, language, params = {}) {
  const notif = notifications[key];
  if (!notif) return { title: key, body: '' };
  
  let title = notif.title[language] || notif.title.en;
  let body = notif.body[language] || notif.body.en;
  
  // Replace parameters
  Object.keys(params).forEach(param => {
    const value = params[param];
    title = title.replace(`{${param}}`, value);
    body = body.replace(`{${param}}`, value);
  });
  
  return { title, body };
}

/**
 * Firestore trigger: Send notifications when order status changes
 * Triggers on: orders/{orderId} document updates
 */
exports.onOrderStatusChange = functions.firestore
  .document('orders/{orderId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const orderId = context.params.orderId;

    console.log(`📦 Order ${orderId} status changed: ${before.status} → ${after.status}`);

    try {
      // 1. NEW ORDER - Payment succeeded, order created (awaiting_pickup)
      if (before.status !== 'awaiting_pickup' && after.status === 'awaiting_pickup') {
        console.log('🎉 New order notification to seller');
        
        const language = await getUserLanguage(after.sellerId);
        const buyerName = after.buyerName || 'Customer';
        const productTitle = after.productTitle || 'Product';
        const price = after.price || 0;
        const currency = after.currency || 'RON';
        
        const notif = getNotification('new_order', language, {
          buyer: buyerName,
          product: productTitle,
          amount: price.toFixed(0),
          currency: currency,
        });
        
        await sendNotificationToUser(after.sellerId, {
          title: notif.title,
          body: notif.body,
          data: {
            type: 'new_order',
            orderId: orderId,
            screen: 'orders',
            priority: 'high',
            category: 'order_confirmed',
          },
        });
      }

      // 2. ORDER SHIPPED - Seller marked as shipped
      if (before.status !== 'shipped' && after.status === 'shipped') {
        console.log('📦 Order shipped notification to buyer');
        
        const language = await getUserLanguage(after.buyerId);
        const productTitle = after.productTitle || 'Your order';
        
        const notif = getNotification('order_shipped', language, {
          product: productTitle,
        });
        
        await sendNotificationToUser(after.buyerId, {
          title: notif.title,
          body: notif.body,
          data: {
            type: 'order_shipped',
            orderId: orderId,
            screen: 'orders',
          },
        });
      }

      // 3. ORDER DELIVERED - Carrier marked as delivered
      if (before.status !== 'delivered' && after.status === 'delivered') {
        console.log('✅ Order delivered notifications');
        
        const productTitle = after.productTitle || 'Product';
        const payment = after.payment || {};
        const userTotal = payment.userTotal || 0;
        const currency = after.currency || 'RON';
        
        // Notify seller about payout
        const sellerLanguage = await getUserLanguage(after.sellerId);
        const sellerNotif = getNotification('order_delivered_seller', sellerLanguage, {
          amount: userTotal.toFixed(2),
          currency: currency,
          product: productTitle,
        });
        
        await sendNotificationToUser(after.sellerId, {
          title: sellerNotif.title,
          body: sellerNotif.body,
          data: {
            type: 'order_delivered_seller',
            orderId: orderId,
            screen: 'orders',
            priority: 'high',
            category: 'order_delivered',
          },
        });

        // Notify buyer about delivery
        const buyerLanguage = await getUserLanguage(after.buyerId);
        const buyerNotif = getNotification('order_delivered_buyer', buyerLanguage, {
          product: productTitle,
        });
        
        await sendNotificationToUser(after.buyerId, {
          title: buyerNotif.title,
          body: buyerNotif.body,
          data: {
            type: 'order_delivered_buyer',
            orderId: orderId,
            screen: 'orders',
            priority: 'high',
            category: 'order_delivered',
          },
        });
      }

      // 4. CARRIER PICKED UP - Tracking number added
      const beforeTracking = before.shipping?.trackingNumber;
      const afterTracking = after.shipping?.trackingNumber;
      
      if (!beforeTracking && afterTracking) {
        console.log('🚚 Carrier pickup notification to buyer');
        
        const language = await getUserLanguage(after.buyerId);
        const carrier = after.shipping?.carrier || 'Courier';
        const trackingShort = afterTracking.substring(Math.max(0, afterTracking.length - 6));
        
        const notif = getNotification('package_picked_up', language, {
          carrier: carrier,
          tracking: trackingShort,
        });
        
        await sendNotificationToUser(after.buyerId, {
          title: notif.title,
          body: notif.body,
          data: {
            type: 'carrier_pickup',
            orderId: orderId,
            trackingNumber: afterTracking,
            screen: 'orders',
          },
        });
      }

      // 5. ORDER CANCELLED
      if (before.status !== 'cancelled' && after.status === 'cancelled') {
        console.log('❌ Order cancelled notifications');
        
        const productTitle = after.productTitle || 'Order';
        
        // Decrement soldCount since order was cancelled
        const productId = after.productId;
        if (productId) {
          try {
            await admin.firestore().collection('products').doc(productId).update({
              soldCount: admin.firestore.FieldValue.increment(-1),
              inventoryCount: admin.firestore.FieldValue.increment(1),
            });
            console.log(`✅ Decremented soldCount and restored inventory for product ${productId}`);
          } catch (productError) {
            console.error(`⚠️ Failed to update product soldCount:`, productError.message);
          }
        }
        
        // Notify both buyer and seller
        const [buyerLanguage, sellerLanguage] = await Promise.all([
          getUserLanguage(after.buyerId),
          getUserLanguage(after.sellerId),
        ]);
        
        const buyerNotif = getNotification('order_cancelled', buyerLanguage, {
          product: productTitle,
        });
        
        const sellerNotif = getNotification('order_cancelled', sellerLanguage, {
          product: productTitle,
        });
        
        await Promise.all([
          sendNotificationToUser(after.buyerId, {
            title: buyerNotif.title,
            body: buyerNotif.body,
            data: {
              type: 'order_cancelled',
              orderId: orderId,
              screen: 'orders',
            },
          }),
          sendNotificationToUser(after.sellerId, {
            title: sellerNotif.title,
            body: sellerNotif.body,
            data: {
              type: 'order_cancelled',
              orderId: orderId,
              screen: 'orders',
            },
          }),
        ]);
      }

      // 6. ORDER RETURNED
      if (before.status !== 'returned' && after.status === 'returned') {
        console.log('↩️ Order returned notification to seller');
        
        const productTitle = after.productTitle || 'Order';
        
        // Decrement soldCount since order was returned
        const productId = after.productId;
        if (productId) {
          try {
            await admin.firestore().collection('products').doc(productId).update({
              soldCount: admin.firestore.FieldValue.increment(-1),
              inventoryCount: admin.firestore.FieldValue.increment(1),
            });
            console.log(`✅ Decremented soldCount and restored inventory for product ${productId}`);
          } catch (productError) {
            console.error(`⚠️ Failed to update product soldCount:`, productError.message);
          }
        }
        
        const language = await getUserLanguage(after.sellerId);
        
        const notif = getNotification('order_returned', language, {
          product: productTitle,
        });
        
        await sendNotificationToUser(after.sellerId, {
          title: notif.title,
          body: notif.body,
          data: {
            type: 'order_returned',
            orderId: orderId,
            screen: 'orders',
          },
        });
      }

    } catch (error) {
      console.error('❌ Error sending order notification:', error);
      // Don't throw - we don't want to fail the order update
    }
  });

/**
 * Firestore trigger: Send notification when new message is received
 * Triggers on: conversations/{conversationId}/messages/{messageId} document creates
 */
exports.onNewMessage = functions.firestore
  .document('conversations/{conversationId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const conversationId = context.params.conversationId;

    console.log(`💬 New message in conversation ${conversationId}`);

    try {
      // Get conversation to find the recipient
      const conversationDoc = await admin.firestore()
        .collection('conversations')
        .doc(conversationId)
        .get();

      if (!conversationDoc.exists) {
        console.log('⚠️ Conversation not found');
        return;
      }

      const conversation = conversationDoc.data();
      const participants = conversation.participants || [];
      
      // Find recipient (not the sender)
      const recipientId = participants.find(id => id !== message.senderId);
      
      if (!recipientId) {
        console.log('⚠️ No recipient found');
        return;
      }

      const senderName = message.senderName || 'Someone';
      const messageText = message.text || 'Sent a message';
      const productTitle = conversation.productTitle || 'Product';

      await sendNotificationToUser(recipientId, {
        title: senderName,
        body: messageText.length > 100 ? messageText.substring(0, 97) + '...' : messageText,
        data: {
          type: 'new_message',
          conversationId: conversationId,
          senderId: message.senderId,
          productId: conversation.productId || '',
          productTitle: productTitle,
          screen: 'chat',
        },
      });

    } catch (error) {
      console.error('❌ Error sending message notification:', error);
    }
  });

/**
 * Firestore trigger: Send notification when offer is accepted
 * Triggers on: offers/{offerId} document updates
 */
exports.onOfferAccepted = functions.firestore
  .document('offers/{offerId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const offerId = context.params.offerId;

    // Only notify when offer status changes to accepted
    if (before.status !== 'accepted' && after.status === 'accepted') {
      console.log(`🤝 Offer ${offerId} accepted`);

      try {
        const language = await getUserLanguage(after.buyerId);
        const offeredPrice = after.offeredPrice || after.offered_price || 0;
        const currency = after.currency || 'RON';
        const productTitle = after.productTitle || 'Product';

        const notif = getNotification('offer_accepted', language, {
          amount: offeredPrice.toFixed(0),
          currency: currency,
          product: productTitle,
        });

        await sendNotificationToUser(after.buyerId, {
          title: notif.title,
          body: notif.body,
          data: {
            type: 'offer_accepted',
            offerId: offerId,
            productId: after.productId || '',
            screen: 'product',
          },
        });

      } catch (error) {
        console.error('❌ Error sending offer notification:', error);
      }
    }
  });
