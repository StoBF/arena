# Hero Manager API

## Опис

Hero Manager API — це асинхронний FastAPI-сервер для керування героями, інвентарем, аукціонами та ставками з JWT-автентифікацією, rate-limit, CORS та сучасною структурою сервісів.

---

## Швидкий старт

1. **Склонуйте репозиторій та перейдіть у директорію проекту**
2. **Створіть .env на основі .env.example**
   ```sh
   cp .env.example .env
   # Заповніть свої значення
   ```
3. **Встановіть залежності**
   ```sh
   pip install -r requirements.txt
   ```
4. **Запустіть сервер**
   ```sh
   export PYTHONPATH=.
   python -m uvicorn main:app --reload
   ```
   або для Windows:
   ```sh
   set PYTHONPATH=.
   python -m uvicorn main:app --reload
   ```

---

## Docker Compose (опційно)

1. **Створіть docker-compose.yml** (приклад не надано, але підтримується Postgres, FastAPI)
2. **Запустіть**
   ```sh
   docker-compose up --build
   ```

---

## .env

Всі секрети та налаштування зберігаються у .env (див. .env.example).

---

## Тестування

1. **Встановіть pytest**
   ```sh
   pip install pytest
   ```
2. **Запустіть тести**
   ```sh
   pytest tests/
   ```

---

## Критичні тести (мають бути у tests/):
- `test_generate_hero.py`: детермінованість генерації героя (через seed)
- `test_place_bid.py`: атомарність і коректність ставок
- `test_authenticated_user.py`: валідація JWT

---

## Залежності
- FastAPI
- SQLAlchemy (async)
- asyncpg/aiosqlite
- slowapi
- python-dotenv
- pydantic

---

## Контакти

[Ваші контакти або посилання на документацію]

---

## Аукціон: предмети, герої, ставки, автоставки

### Основні можливості
- Аукціон предметів (Auction): продаж ресурсів, спорядження, стеків (quantity)
- Аукціон героїв (AuctionLot): продаж героя з перевірками (без екіпіровки, не мертвий, не на навчанні)
- Система ставок (Bid) — резервування коштів, повернення резерву попередньому лідеру
- Автоставки (AutoBid) — користувач може задати максимальну суму, яка резервується
- Вся економіка через User.balance та User.reserved
- Таймери: автоматичне закриття аукціонів/лотів по end_time (фоновий таск)

### Основні моделі
- **Auction**: item_id, seller_id (user), winner_id (user), quantity, start_price, current_price, end_time, status
- **AuctionLot**: hero_id, seller_id (user), winner_id (user), starting_price, current_price, buyout_price, end_time, is_active
- **Bid**: auction_id або lot_id, bidder_id (user), amount
- **AutoBid**: auction_id або lot_id, user_id, max_amount

### Основні API endpoints

#### Аукціон предметів
- `POST /auctions/` — створити аукціон (item_id, start_price, duration, quantity)
- `GET /auctions/` — список активних аукціонів
- `POST /auctions/{auction_id}/cancel` — скасувати аукціон (продавець)
- `POST /auctions/{auction_id}/close` — закрити аукціон (визначити переможця)

#### Аукціон героїв
- `POST /auctions/lots` — створити лот героя (hero_id, starting_price, duration, buyout_price)
- `GET /auctions/lots` — список активних лотів
- `POST /auctions/lots/{lot_id}/close` — закрити лот (визначити переможця)
- `POST /auctions/lots/{lot_id}/delete` — видалити лот (якщо не було ставок)

#### Ставки
- `POST /bids/` — зробити ставку (auction_id або lot_id, amount)
- `GET /bids/` — список ставок користувача

#### Автоставки
- `POST /auctions/autobid` — встановити автоставку (auction_id або lot_id, max_amount)

### Edge cases та перевірки
- Не можна ставити на свій лот/аукціон
- Не можна зробити ставку, якщо недостатньо коштів (balance - reserved)
- При перебитті ставки резерв попереднього лідера повертається
- При закритті аукціону/лоту переможець отримує предмет/героя, продавець — кошти
- Якщо ставок не було — предмет/герой повертається продавцю
- Герой не може бути виставлений, якщо екіпірований, мертвий або на навчанні
- Автоставка резервує всю max_amount одразу

### Приклад створення аукціону (предмет)
```json
POST /auctions/
{
  "item_id": 101,
  "start_price": 500,
  "duration": 24,
  "quantity": 3
}
```

### Приклад ставки
```json
POST /bids/
{
  "auction_id": 1,
  "amount": 600
}
```

### Приклад автоставки
```json
POST /auctions/autobid
{
  "auction_id": 1,
  "max_amount": 2000
}
```

---

## Склад користувача, екіпірування, крафт, типи предметів, слоти

### Основні зміни
- Весь інвентар тепер глобальний для користувача (Stash), а не для героя
- Всі предмети зберігаються у складі користувача (user_id, item_id, quantity)
- Екіпірування предметів: предмет береться зі складу, екіпірується на героя у відповідний слот
- Слоти героя мають космічну тематику: weapon, helmet, spacesuit, boots, artifact, shield, gadget, implant, utility_belt тощо
- Типи предметів: equipment, artifact, resource, material, consumable
- Крафт: (планується) — створення предметів з ресурсів зі складу

### Основні моделі
- **Stash**: user_id, item_id, quantity (унікальний user+item)
- **Item**: name, description, type, slot_type, бонуси (bonus_strength, ...)
- **Equipment**: hero_id, item_id, slot (унікальний hero+slot)

### Основні API endpoints
- `POST /inventory/` — додати предмет у склад (user_id, item_id, quantity)
- `GET /inventory/` — отримати список предметів у складі користувача
- `DELETE /inventory/{id}` — видалити предмет зі складу
- `POST /equipment/` — екіпірувати предмет на героя (hero_id, item_id, slot)
- `POST /equipment/unequip` — зняти предмет зі слоту героя
- `POST /craft/` — (планується) створити предмет з ресурсів

### Edge cases та перевірки
- Не можна екіпірувати предмет, якщо його немає у складі
- Не можна екіпірувати предмет у невірний слот (item.slot_type != slot)
- Не можна екіпірувати предмет на чужого героя
- Не можна екіпірувати, якщо герой мертвий, на навчанні або на аукціоні
- При знятті предмета він повертається у склад
- У складі quantity агрегується по user+item
- При додаванні предмета, якщо такий вже є — quantity збільшується
- При видаленні/екіпіруванні — quantity зменшується або запис видаляється

### Приклад додавання предмета у склад
```json
POST /inventory/
{
  "item_id": 101,
  "quantity": 2
}
```

### Приклад екіпірування
```json
POST /equipment/
{
  "hero_id": 1,
  "item_id": 101,
  "slot": "weapon"
}
```

### Приклад крафту (планується)
```json
POST /craft/
{
  "recipe_id": 5
}
```

### Список слотів (космічна тематика)
- weapon
- helmet
- spacesuit
- boots
- artifact
- shield
- gadget
- implant
- utility_belt

---

## Крафт, ресурси, рецепти

### Основні можливості
- Крафт предметів з ресурсів зі складу користувача (Stash)
- Рецепти з фіксованим набором інгредієнтів та результатом
- Черга крафту: асинхронне створення предметів (таймер craft_time)
- Всі ресурси та результати крафту зберігаються у складі користувача

### Основні моделі
- **GameResource**: id, name, description — ресурс для крафту, дропа, економіки
- **CraftRecipe**: id, name, result_item_id, ingredients (JSON: [{item_id, quantity}]), craft_time
- **CraftQueue**: user_id, recipe_id, quantity, started_at, finish_at, status
- **CraftedItem**: user_id, recipe_id, quantity, created_at (історія крафту)

### Основні API endpoints
- `GET /workshop/recipes` — список доступних рецептів
- `POST /workshop/craft` — почати крафт (recipe_id, quantity)
- `GET /workshop/queue` — переглянути чергу крафту користувача
- `POST /workshop/finish/{queue_id}` — завершити крафт (отримати предмет)

### Edge cases та перевірки
- Не можна почати крафт без достатньої кількості ресурсів у складі
- Після старту крафту ресурси списуються одразу
- Завершити крафт можна лише після закінчення таймера (finish_at)
- Результат крафту додається у склад користувача
- Можна крафтити кілька предметів одразу (quantity)
- Якщо крафт_time = 0 — предмет створюється миттєво

### Приклад рецепта
```json
{
  "id": 1,
  "name": "Laser Sword",
  "result_item_id": 101,
  "ingredients": [
    {"item_id": 201, "quantity": 2},
    {"item_id": 202, "quantity": 1}
  ],
  "craft_time": 60
}
```

### Приклад старту крафту
```json
POST /workshop/craft
{
  "recipe_id": 1,
  "quantity": 2
}
```

### Приклад черги крафту
```json
GET /workshop/queue
[
  {
    "id": 5,
    "user_id": 1,
    "recipe_id": 1,
    "quantity": 2,
    "started_at": "2024-06-01T12:00:00Z",
    "finish_at": "2024-06-01T12:02:00Z",
    "status": "pending"
  }
]
```

### Приклад завершення крафту
```json
POST /workshop/finish/5
{
  "id": 3,
  "user_id": 1,
  "recipe_id": 1,
  "quantity": 2,
  "created_at": "2024-06-01T12:02:01Z"
}
```

### PvP/PvE ресурси та крафт
- Крафт предметів може вимагати PvP (Сталь, Срібло, Кристал, Тканина хаосу) та PvE ресурси (унікальні для рейдбосів)
- Рецепт містить окремо pvp_resources та pve_resources

### Обмеження
- Не можна крафтити епічний/легендарний предмет більше 1 разу на добу
- Якщо не вистачає хоча б одного ресурсу — крафт не починається
- Мутація: шанс 0.5% при крафті (is_mutated=True)

### Edge cases
- Спроба крафту без PvP/PvE ресурсів — 400
- Спроба disenchant чужого/неіснуючого предмета — 400
- Спроба finish_craft до ready_at — 400
- Спроба крафту за невалідним recipe_id — 400

### Ендпоінти майстерні
- `GET /workshop/available` — рецепти, які можна скрафтити з поточних ресурсів
- `POST /workshop/craft/{recipe_id}` — запуск крафту
- `GET /workshop/queue` — черга крафту
- `POST /workshop/finish/{queue_id}` — завершити крафт
- `POST /workshop/disenchant/{item_id}` — розпорошити предмет (повертає 50% ресурсів)

### Приклад крафту з PvP/PvE ресурсами
```json
POST /workshop/craft/1
{
  // headers: Authorization: Bearer ...
}
```

### Приклад disenchant
```json
POST /workshop/disenchant/1
{
  // headers: Authorization: Bearer ...
}
// Відповідь:
{
  "returned_resources": {
    "1": 2,   // 50% від 4 Сталі
    "101": 1  // 50% від 2 Плазмових батарей
  }
}
```

### Інтеграційний сценарій
1. Користувач отримує ресурси (Сталь, Плазмова батарея)
2. GET /workshop/available — бачить доступний рецепт
3. POST /workshop/craft/{recipe_id} — запускає крафт
4. GET /workshop/queue — бачить чергу
5. POST /workshop/finish/{queue_id} — отримує предмет
6. POST /workshop/disenchant/{item_id} — розпорошує предмет, отримує частину ресурсів назад

### Приклад edge case
```json
POST /workshop/craft/9999 // неіснуючий рецепт
// 400 Bad Request

POST /workshop/disenchant/9999 // неіснуючий предмет
// 400 Bad Request
```

---

## Масштабований чат (WebSocket + Redis Pub/Sub)

### Архітектура
- Всі повідомлення чату (general, trade, private) передаються через Redis Pub/Sub.
- Кожен WebSocket-клієнт підписується на відповідний канал у Redis.
- Підтримується горизонтальне масштабування (кілька процесів/воркерів FastAPI, кілька серверів).
- Всі повідомлення доходять до адресата незалежно від процесу, в якому піднято WebSocket.

### Канали
- `chat:general` — глобальний чат
- `chat:trade` — торговий чат
- `chat:private:{user_id}` — приватні повідомлення для user_id

### Підключення WebSocket
```js
// General
const ws = new WebSocket("wss://yourhost/ws/general?token=...JWT...");
ws.onmessage = (msg) => console.log(msg.data);
ws.send("Привіт!");

// Trade
const ws = new WebSocket("wss://yourhost/ws/trade?token=...JWT...");

// Private
const ws = new WebSocket("wss://yourhost/ws/private?token=...JWT...");
ws.send(JSON.stringify({to: 42, text: "Привіт, 42!"}));
```

### Переваги
- Масштабованість: працює з будь-якою кількістю воркерів/серверів
- Всі повідомлення гарантовано доходять до адресата
- Можна додати нові канали без зміни архітектури

### Edge cases
- Якщо користувач не підключений — повідомлення зберігається лише у Redis (історія не зберігається автоматично)
- Якщо Redis недоступний — чат тимчасово не працює
- Всі перевірки авторизації виконуються на рівні WebSocket (JWT у query params)

### Схема каналів
```
[Client] <--ws--> [FastAPI worker] <---> [Redis Pub/Sub] <---> [FastAPI worker] <--ws--> [Client]
```

### Системні повідомлення
- Для надсилання системних повідомлень використовуйте:
```python
from app.core.redis_pubsub import publish_message
await publish_message("private", {"type": "system", "text": "Ваша дія успішна!"}, user_id=42)
```

---

## Advanced логування, Sentry, Prometheus

### Логування
- Всі логи пишуться у файл `server.log` з ротацією (5 MB, 5 бекапів) та в консоль.
- Окремі рівні для модулів: `app`, `hero_gen`, `sqlalchemy.engine`, `uvicorn.error`, `uvicorn.access`.
- Для зміни рівня логування змініть відповідний логгер у `app/core/log_config.py`.
- Приклад:
```python
import logging
logger = logging.getLogger("app")
logger.info("User registered: %s", user.email)
logger.error("Critical error!")
```

### Sentry (опційно)
- Для збору помилок у Sentry додайте у `.env`:
```
SENTRY_DSN=ваш_dsn_з_Sentry
```
- Sentry автоматично підключиться для всіх помилок (через sentry_sdk).

### Prometheus
- Для збору метрик додано middleware Prometheus (`prometheus_client`).
- Метрики доступні на `/metrics` (для Prometheus scrape).
- Збираються: кількість запитів, помилки, час відповіді по endpoint.
- Приклад scrape-конфігурації Prometheus:
```yaml
scrape_configs:
  - job_name: 'hero_manager'
    static_configs:
      - targets: ['localhost:8081']
```

### Переваги
- Логи з ротацією — не переповнюють диск
- Sentry — автоматичний збір помилок з trace
- Prometheus — моніторинг продуктивності, алерти

### Edge cases
- Якщо Sentry не встановлено — просто ігнорується
- Якщо Prometheus не підключено — API працює як завжди 