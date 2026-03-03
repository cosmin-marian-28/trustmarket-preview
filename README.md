# TrustMarket — Full-Stack Marketplace (Portfolio Preview)

This is a curated selection of files from a production marketplace application I built solo. The full project contains 50+ Cloud Functions, 30+ Flutter pages, and 50+ database migrations. Only architecture-representative files are shared here — payment logic, AI pipelines, and identity verification are kept private.

## Tech Stack

- **Frontend:** Flutter/Dart (iOS, Android, Web)
- **Backend:** Firebase Cloud Functions (Node.js 20)
- **Database:** Supabase (PostgreSQL 17) with Row-Level Security
- **Payments:** Stripe Connect (escrow, delayed capture, payouts)
- **AI:** OpenAI, Anthropic, Google Generative AI (product analysis, dispute resolution)
- **Identity:** TensorFlow.js + face-api (KYC verification)
- **Real-time:** Supabase Realtime + Firebase Cloud Messaging
- **Voice/Video:** Agora SDK + custom WebSocket server

## What's Included

### Frontend — Flutter/Dart (`lib/`)

| File | What it shows |
|------|--------------|
| `lib/main.dart` | App entry point — multi-SDK init sequence (Supabase, Firebase, Stripe), auth gate with StreamBuilder, orientation lock, error handling |
| `lib/services/supabase_service.dart` | Singleton service pattern — auth, CRUD, real-time subscriptions, storage, all through one abstraction |
| `lib/services/language_service.dart` | i18n system with SharedPreferences persistence |
| `lib/services/currency_service.dart` | Multi-currency support with user preference persistence |
| `lib/services/currency_conversion_service.dart` | Live currency conversion with caching |
| `lib/services/geolocation_service.dart` | Location services abstraction |
| `lib/services/advanced_search_service.dart` | Full-text search with filters, history, and suggestions |
| `lib/services/image_optimization_service.dart` | Image compression and optimization pipeline |
| `lib/pages/home_page.dart` | Main marketplace view — multi-layout (grid/scroll/list), real-time updates, pull-to-refresh |
| `lib/pages/product_detail_page.dart` | Product detail with chat, offers, shipping estimation |
| `lib/pages/chat_page.dart` | Real-time chat with message persistence |
| `lib/widgets/product_card_widget.dart` | Reusable product card — cached images, price conversion, status badges |
| `lib/widgets/search_widgets.dart` | Search UI components with debounce and history |
| `lib/widgets/price_with_conversion_widget.dart` | Price display with live currency conversion |
| `lib/widgets/shimmer_loading.dart` | Skeleton loading states |
| `lib/helpers/image_helper.dart` | Image processing utilities |
| `lib/helpers/geolocation_helper.dart` | Geo utilities (distance, formatting) |
| `lib/utils/order_status.dart` | Order state machine and status transitions |
| `lib/utils/trust.dart` | Trust score calculation logic |
| `lib/constants/translations.dart` | Multi-language translation map |

### Backend — Cloud Functions (`functions/`)

| File | What it shows |
|------|--------------|
| `functions/index.js` | Main entry — modular exports for 50+ functions organized by domain |
| `functions/package.json` | Backend dependencies (Stripe, AI SDKs, TensorFlow, image processing) |
| `functions/shipping/index.js` | Shipping module entry — clean module pattern |
| `functions/shipping/calculator.js` | Shipping cost calculation engine |
| `functions/shipping/estimation.js` | Delivery time estimation |
| `functions/shipping/tracking.js` | Shipment tracking integration |
| `functions/shipping/deadlines.js` | Delivery deadline enforcement |
| `functions/shipping/utils.js` | Shipping helper utilities |
| `functions/notifications/index.js` | Notification module entry |
| `functions/notifications/fcm.js` | Firebase Cloud Messaging integration |
| `functions/notifications/orderNotifications.js` | Order lifecycle notification triggers |
| `functions/utils/validation.js` | Input validation and sanitization |
| `functions/utils/errors.js` | Centralized error handling |
| `functions/utils/retries.js` | Retry logic with exponential backoff |
| `functions/utils/idempotency.js` | Idempotency keys for safe retries |
| `functions/utils/trustScore.js` | Trust score computation |

### Database (`supabase/`)

| File | What it shows |
|------|--------------|
| `supabase/migrations/20250130000001_initial_schema.sql` | Core schema — users, products, services, gigs, orders, conversations, disputes, with RLS policies |

### Config

| File | What it shows |
|------|--------------|
| `pubspec.yaml` | Flutter dependencies and project config |
| `analysis_options.yaml` | Dart linting rules |

## Full Architecture (not all shown here)

```
├── lib/                          # Flutter frontend
│   ├── pages/          (31)      # Feature screens
│   ├── services/       (17)      # Business logic layer
│   ├── widgets/        (16)      # Reusable UI components
│   ├── helpers/         (6)      # Utility helpers
│   ├── utils/           (8)      # Domain utilities
│   ├── models/                   # Data models
│   ├── constants/                # Translations, payment config
│   └── core/                     # Core providers
│
├── functions/                    # Firebase Cloud Functions (Node.js)
│   ├── payments/       (18 fn)   # Stripe Connect, escrow, payouts ⛔
│   ├── shipping/        (4 fn)   # Labels, tracking, estimation ✅
│   ├── products/        (3 fn)   # AI analysis ⛔
│   ├── services/        (5 fn)   # Service bookings
│   ├── gigs/                     # Gig management
│   ├── identity/                 # Face verification, KYC ⛔
│   ├── disputes/                 # AI dispute resolution ⛔
│   ├── chat/                     # Chat moderation
│   ├── notifications/            # FCM push notifications ✅
│   ├── offers/                   # Offer token system
│   ├── orders/                   # Group buy logic
│   ├── support/                  # Conversational support
│   ├── siri/                     # Siri Shortcuts integration
│   └── utils/                    # Shared utilities ✅
│
├── supabase/                     # Database
│   └── migrations/    (50+)      # PostgreSQL schema + RLS policies ✅
│
└── voice-server/                 # WebSocket voice chat server
```

✅ = included in preview | ⛔ = private (business logic)

## What's NOT Included (and why)

- **Payment processing** — Stripe Connect integration with escrow, delayed capture, and automated payouts. Core business logic.
- **AI product analysis** — Multi-model pipeline (OpenAI + Anthropic + Gemini) for product validation. Competitive advantage.
- **Identity verification** — TensorFlow.js face matching with liveness detection. Security-sensitive.
- **Dispute resolution** — AI-powered dispute analysis and automated resolution. Business logic.
- **Offer token system** — Cryptographic offer validation. Security-sensitive.
- **API keys and credentials** — Obviously.

## Contact

Built by Cosmin — full-stack developer with experience in Flutter, Node.js, PostgreSQL, Stripe, and AI integrations.
