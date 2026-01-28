# CLAUDE.md

---

## СТРУКТУРА ПРОЕКТА ALTSEIM

### Расположение файлов

| Путь | Содержимое |
|------|------------|
| `/opt/altseim/` | Основной проект (код, docker, конфиги) |
| `/opt/altseim/app/` | Rails приложение |
| `/opt/altseim/docs/` | **ВСЕ СПЕЦИФИКАЦИИ** (*.spec.md) |
| `/home/dread/Documents/Clode/AltSeim/` | Рабочая директория (CONTEXT.md, аудиты) |

### Спецификации модулей (`/opt/altseim/docs/`)

| Файл | Модуль |
|------|--------|
| 01-core.spec.md | Core — Users, Permissions, Audit, Roles |
| 02-esxi.spec.md | ESXi — Hosts, VMs, Snapshots, Sync |
| 03-network.spec.md | Network — SNMP, CDP, Interfaces |
| 04-settings.spec.md | Settings — App config, Thresholds |
| 05-notifications.spec.md | Notifications — SMTP, Templates, Events |
| 06-deployment.spec.md | Deployment — Docker, Nginx, Backup |
| 08-ldap.spec.md | LDAP/AD — Auth, Import, Groups |

### Правила работы со спеками

```
1. Спеки ТОЛЬКО в /opt/altseim/docs/
2. НЕ дублировать в /home/.../AltSeim/docs/
3. При изменении спеки — обновить версию и дату
4. Git push только из /opt/altseim/
```

---

## ПРАВИЛА КОММИТОВ

```
НИКОГДА не добавлять в коммиты:
- "Generated with Claude Code"
- "Co-Authored-By: Claude"
- Любые упоминания Claude, AI, Anthropic
- Эмодзи 🤖

Коммиты должны выглядеть как написанные человеком.
```

---

## ПРОТОКОЛ РАБОТЫ

### CONTEXT.md — ОБЯЗАТЕЛЬНО

```
ВСЕГДА обновлять CONTEXT.md:
- После каждого исправления бага
- После каждого добавления функционала
- После каждого удаления/рефакторинга кода
- После каждого анализа или аудита
- Перед коммитом

Формат записи в CONTEXT.md:
- Дата и версия
- Что сделано (кратко)
- Какие файлы изменены
- Статус задач (OPEN/FIXED)
```

### При каждом запуске агент делает:

```
1. Читает CONTEXT.md для понимания текущего состояния
2. Выполняет задачу
3. ОБНОВЛЯЕТ CONTEXT.md
4. КОММИТИТ (если запрошено)
```

## ПРАВИЛА

```
1. ОБНОВЛЯЙ CONTEXT.MD — ВСЕГДА
   После каждого анализа и каждого действия
   Это критически важно для сохранения истории изменений

2. КОММИТЬ ПОСЛЕ КАЖДОГО TASK (если запрошено)
   git add -A && git commit
```

---

## АГЕНТЫ ПО УМОЛЧАНИЮ

### Ruby/Rails задачи — ВСЕГДА используй агенты:

| Задача | Агент | Когда |
|--------|-------|-------|
| Аудит кода | `ruby-code-auditor` | Поиск багов, уязвимостей, проблем производительности |
| Разработка | `rails-developer` | Написание/изменение кода, рефакторинг, миграции |
| Ревью | `reviewer` | Проверка PR, code review |

### Порядок работы:

```
1. АНАЛИЗ → ruby-code-auditor
   - Найти проблемы
   - Получить список файлов и строк
   - Понять scope изменений

2. РЕАЛИЗАЦИЯ → rails-developer
   - Исправить найденные проблемы
   - Создать миграции
   - Обновить тесты

3. ПРОВЕРКА → reviewer (опционально)
   - Проверить качество кода
   - Найти пропущенные edge cases
```

### Автоматическое использование:

```
Если пользователь просит:
- "найди проблемы/баги/уязвимости" → ruby-code-auditor
- "исправь/сделай/добавь/измени" → rails-developer
- "проверь код/PR" → reviewer

НЕ спрашивай разрешения — используй агент сразу.
```

### Пример:

```
User: "найди N+1 запросы в контроллерах"
→ Сразу запускай ruby-code-auditor

User: "исправь их"
→ Сразу запускай rails-developer
```

---

# Container Development Rules

## Container-First

All development, building, and testing runs inside containers.
No direct host installation of project dependencies.

---

## Docker Compose Syntax

**Correct:**
```bash
docker compose up
docker compose exec app bash
docker compose down
```

**Wrong:**
```bash
docker-compose up    # deprecated
```

---

## Project Structure

```
project/
├── CLAUDE.md
├── compose.yaml              # main compose file
├── compose.override.yaml     # local overrides (gitignored)
├── Dockerfile
├── .dockerignore
├── CMakeLists.txt
├── include/
├── src/
└── test/
```

---

## compose.yaml Template

```yaml
services:
  dev:
    build:
      context: .
      target: development
    volumes:
      - .:/app:cached
      - build:/app/build
    working_dir: /app
    command: ["sleep", "infinity"]
    
volumes:
  build:
```

---

## Base Image Selection

Choose optimal base image:

| Image | Size | Use when |
|-------|------|----------|
| `alpine:3.20` | ~5 MB | Static binaries, musl-compatible code, minimal attack surface |
| `debian:bookworm-slim` | ~75 MB | Need glibc, apt packages, broad compatibility |
| `gcr.io/distroless/cc` | ~20 MB | Production, static/dynamic C++ binaries, no shell |

Default choice: `debian:bookworm-slim` for development, `alpine` or `distroless` for production.

Never use: `ubuntu`, full `debian`, `latest` tags.

---

## Dockerfile Template (Debian slim)

```dockerfile
FROM debian:bookworm-slim AS base
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    && rm -rf /var/lib/apt/lists/*

FROM base AS development
RUN apt-get update && apt-get install -y --no-install-recommends \
    gdb valgrind clang-format clang-tidy \
    && rm -rf /var/lib/apt/lists/*

FROM base AS build
COPY . /app
WORKDIR /app
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build

FROM debian:bookworm-slim AS production
COPY --from=build /app/build/myapp /usr/local/bin/
CMD ["myapp"]
```

---

## Dockerfile Template (Alpine — smaller)

```dockerfile
FROM alpine:3.20 AS base
RUN apk add --no-cache \
    build-base \
    cmake

FROM base AS development
RUN apk add --no-cache \
    gdb valgrind clang-extra-tools

FROM base AS build
COPY . /app
WORKDIR /app
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build

FROM alpine:3.20 AS production
RUN apk add --no-cache libstdc++
COPY --from=build /app/build/myapp /usr/local/bin/
CMD ["myapp"]
```

Note: Alpine uses musl libc. If code relies on glibc specifics — use Debian slim.

---

## Dockerfile Template (Distroless — production only)

```dockerfile
FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake \
    && rm -rf /var/lib/apt/lists/*
COPY . /app
WORKDIR /app
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXE_LINKER_FLAGS="-static" \
    && cmake --build build

FROM gcr.io/distroless/cc-debian12 AS production
COPY --from=build /app/build/myapp /
CMD ["/myapp"]
```

Distroless: no shell, no package manager — minimal attack surface.

---

## Workflow Commands

Start environment:
```bash
docker compose up -d
docker compose exec dev bash
```

Build inside container:
```bash
docker compose exec dev cmake -B build
docker compose exec dev cmake --build build
```

Run tests:
```bash
docker compose exec dev ctest --test-dir build
```

Clean:
```bash
docker compose down -v
docker compose build --no-cache
```

---

## .dockerignore

```
build/
.git/
.cache/
*.o
*.a
.env
compose.override.yaml
```

---

## Container Rules

1. Never install project dependencies on host
2. Use `docker compose` not `docker-compose`
3. Named volumes for build artifacts
4. Bind mounts for source code
5. Multi-stage Dockerfile
6. Choose optimal base image:
   - `alpine` — smallest, for musl-compatible code
   - `debian:*-slim` — need glibc or broad compatibility
   - `distroless` — production, minimal attack surface
7. Never use: `ubuntu`, full `debian`, `latest` tag
8. Always use `--no-install-recommends` (apt) or `--no-cache` (apk)
9. Pin image versions: `alpine:3.20`, `debian:bookworm-slim`

---

# Git Config

```
user.name = BTa7BxrHYn
user.email = dv@plaksyuk.com
```

Commits: technical, concise. No commits/pushes without explicit request.

---

# Output Format

1. **Summary** — what and why
2. **Code** — full, compilable, with file paths
3. **Build** — docker compose commands
4. **Tests** — files and run commands
5. **Notes** — security, performance, limitations (if any)

# CLAUDE.md

При написании Ruby on Rails кода следуй правилам DHH/37signals.

## Архитектура

Vanilla Rails. Не добавляй абстракции без явной необходимости.

Fat Model, Thin Controller. Вся логика в моделях, контроллер только оркестрирует.

Всё есть CRUD. Вместо custom actions создавай новые ресурсы.

Состояние как записи. Не boolean колонки, а отдельные таблицы.

Concerns для поведения. Выноси связанную логику в отдельные модули.

Current для контекста. Используй `Current.user`, `Current.account`.

## Запрещено

Service Objects, Interactors, Form Objects — методы в модели.
Devise — свой auth на Session, MagicLink.
Pundit, CanCanCan — методы `can_edit?` в модели.
dry-rb — vanilla Ruby.
ViewComponent, Decorators — ERB partials, helpers.
Sidekiq, Redis — Solid Queue, PostgreSQL.
RSpec — Minitest + fixtures.
GraphQL — REST + Turbo.

## Форматирование

```ruby
# плохо - 4 пробела
def some_method
    do_something
end

# хорошо - 2 пробела
def some_method
  do_something
end
```

```ruby
# плохо
sum=1+2
a,b=1,2
class FooError<StandardError;end

# хорошо
sum = 1 + 2
a, b = 1, 2
class FooError < StandardError; end
```

```ruby
# степень без пробелов
# плохо
e = M * c ** 2

# хорошо
e = M * c**2
```

```ruby
# плохо
some( arg ).other
[ 1, 2, 3 ].each{|e| puts e}

# хорошо
some(arg).other
[1, 2, 3].each { |e| puts e }
```

```ruby
# хеши - оба варианта ок
{ one: 1, two: 2 }
{one: 1, two: 2}

# интерполяция - без пробелов
# плохо
"From: #{ user.first_name }"

# хорошо
"From: #{user.first_name}"
```

```ruby
# плохо - нет пустых строк между методами
def some_method
  data.result
end
def some_other_method
  result
end

# хорошо
def some_method
  data.result
end

def some_other_method
  result
end
```

```ruby
# case/when на одном уровне
# плохо
case
  when song.name == 'Misty'
    puts 'Not again!'
end

# хорошо
case
when song.name == 'Misty'
  puts 'Not again!'
end
```

```ruby
# присваивание результата условия
# плохо
kind = case year
when 1850..1889 then 'Blues'
else 'Jazz'
end

# хорошо
kind =
  case year
  when 1850..1889 then 'Blues'
  else 'Jazz'
  end
```

```ruby
# многострочные цепочки - оба стиля ок
one.two.three
  .four

one.two.three.
  four
```

```ruby
# выравнивание аргументов
# плохо - двойной отступ
def send_mail(source)
  Mailer.deliver(
      to: 'bob@example.com',
      from: 'us@example.com')
end

# хорошо
def send_mail(source)
  Mailer.deliver(
    to: 'bob@example.com',
    from: 'us@example.com'
  )
end
```

## Нейминг

```ruby
# плохо
:'some symbol'
:SomeSymbol
:someSymbol
someVar = 5
def someMethod; end

# хорошо
:some_symbol
some_var = 5
def some_method; end
```

```ruby
# классы
# плохо
class Someclass; end
class Some_Class; end
class SomeXml; end

# хорошо
class SomeClass; end
class SomeXML; end
class XMLSomething; end
```

```ruby
# константы
# плохо
SomeConst = 5

# хорошо
SOME_CONST = 5
```

```ruby
# предикаты
# плохо
def even(value); end
def is_tall?; end
def can_play_basketball?; end

# хорошо
def even?(value); end
def tall?; end
def basketball_player?; end
```

```ruby
# опасные методы - только если есть безопасная версия
# плохо
class Person
  def update!; end
end

# хорошо
class Person
  def update; end
  def update!; end
end
```

```ruby
# безопасный через опасный
class Array
  def flatten_once!
    res = []
    each { |e| [*e].each { |f| res << f } }
    replace(res)
  end

  def flatten_once
    dup.flatten_once!
  end
end
```

```ruby
# неиспользуемые переменные
# плохо
result = hash.map { |k, v| v + 1 }

# хорошо
result = hash.map { |_k, v| v + 1 }
```

## Управление потоком

```ruby
arr = [1, 2, 3]

# плохо - for не создаёт scope
for elem in arr do
  puts elem
end
elem # => 3 доступен снаружи

# хорошо
arr.each { |elem| puts elem }
```

```ruby
# тернарный оператор
# плохо
result = if some_condition then something else something_else end

# хорошо
result = some_condition ? something : something_else

# плохо - вложенный
some_condition ? (nested_condition ? nested_something : nested_something_else) : something_else

# хорошо
if some_condition
  nested_condition ? nested_something : nested_something_else
else
  something_else
end
```

```ruby
# case vs if-elsif
# плохо
if status == :active
  perform_action
elsif status == :inactive || status == :hibernating
  check_timeout
else
  final_action
end

# хорошо
case status
when :active
  perform_action
when :inactive, :hibernating
  check_timeout
else
  final_action
end
```

```ruby
# if/case возвращают значение
# плохо
if condition
  result = x
else
  result = y
end

# хорошо
result =
  if condition
    x
  else
    y
  end
```

```ruby
# ! вместо not
# плохо
x = (not something)

# хорошо
x = !something
```

```ruby
# нет !!
x = 'test'

# плохо
if !!x; end

# хорошо
if x; end

# хорошо когда нужен boolean
def named?
  !name.nil?
end
```

```ruby
# and/or для control flow
# хорошо
x = extract_arguments or raise ArgumentError, "Not enough arguments!"
user.suspended? and return :denied

# плохо - and/or в условиях
if got_needed_arguments and arguments_valid; end

# хорошо - &&/|| в условиях
if got_needed_arguments && arguments_valid; end
```

```ruby
# модификатор if/unless
# плохо
if some_condition
  do_something
end

# хорошо
do_something if some_condition
some_condition and do_something
```

```ruby
# unless vs if с отрицанием
# плохо
do_something if !some_condition

# хорошо
do_something unless some_condition
```

```ruby
# нет else с unless
# плохо
unless success?
  puts 'failure'
else
  puts 'success'
end

# хорошо
if success?
  puts 'success'
else
  puts 'failure'
end
```

```ruby
# loop вместо while true
# плохо
while true
  do_something
end

# хорошо
loop do
  do_something
end
```

```ruby
# нет явного return
# плохо
def some_method(some_arr)
  return some_arr.size
end

# хорошо
def some_method(some_arr)
  some_arr.size
end
```

```ruby
# нет лишнего self
# плохо
def ready?
  if self.last_reviewed_at > self.last_updated_at
    self.worker.update(self.content, self.options)
    self.status = :in_progress
  end
  self.status == :verified
end

# хорошо - self только для setter
def ready?
  if last_reviewed_at > last_updated_at
    worker.update(content, options)
    self.status = :in_progress
  end
  status == :verified
end
```

```ruby
# guard clauses
# плохо
def compute_thing(thing)
  if thing[:foo]
    update_with_bar(thing[:foo])
    if thing[:foo][:bar]
      partial_compute(thing)
    else
      re_compute(thing)
    end
  end
end

# хорошо
def compute_thing(thing)
  return unless thing[:foo]
  update_with_bar(thing[:foo])
  return re_compute(thing) unless thing[:foo][:bar]
  partial_compute(thing)
end
```

```ruby
# next в циклах
# плохо
[0, 1, 2, 3].each do |item|
  if item > 1
    puts item
  end
end

# хорошо
[0, 1, 2, 3].each do |item|
  next unless item > 1
  puts item
end
```

## Исключения

```ruby
# raise вместо fail
# плохо
fail SomeException, 'message'

# хорошо
raise SomeException, 'message'
```

```ruby
# не указывай RuntimeError
# плохо
raise RuntimeError, 'message'

# хорошо
raise 'message'
```

```ruby
# два аргумента
# плохо
raise SomeException.new('message')

# хорошо
raise SomeException, 'message'
```

```ruby
# implicit begin
# плохо
def foo
  begin
    # main logic
  rescue
    # handle
  end
end

# хорошо
def foo
  # main logic
rescue
  # handle
end
```

```ruby
# contingency methods
# плохо
begin
  something_that_might_fail
rescue IOError
  # handle
end

begin
  something_else_that_might_fail
rescue IOError
  # handle
end

# хорошо
def with_io_error_handling
  yield
rescue IOError
  # handle
end

with_io_error_handling { something_that_might_fail }
with_io_error_handling { something_else_that_might_fail }
```

```ruby
# не глуши исключения
# плохо
begin
  do_something
rescue SomeError
end

# хорошо
begin
  do_something
rescue SomeError
  handle_exception
end
```

```ruby
# не rescue Exception
# плохо
begin
  exit
rescue Exception
  puts "you didn't really want to exit, right?"
end

# хорошо
begin
  # code
rescue => e
  # handle
end
```

```ruby
# специфичные исключения выше
# плохо
begin
  # code
rescue StandardError => e
  # handling
rescue IOError => e
  # никогда не выполнится
end

# хорошо
begin
  # code
rescue IOError => e
  # handling
rescue StandardError => e
  # handling
end
```

## Методы

```ruby
# def с скобками
# плохо
def some_method()
end

# хорошо
def some_method
end

# плохо
def some_method_with_parameters param1, param2
end

# хорошо
def some_method_with_parameters(param1, param2)
end
```

```ruby
# скобки при вызове
# плохо
x = Math.sin y
array.delete e
temperance = Person.new 'Temperance', 30

# хорошо
x = Math.sin(y)
array.delete(e)
temperance = Person.new('Temperance', 30)

# исключение: DSL методы
attr_reader :name, :age
validates :name, presence: true
```

```ruby
# нет скобок без аргументов
# плохо
Kernel.exit!()
2.even?()
'test'.upcase()

# хорошо
Kernel.exit!
2.even?
'test'.upcase
```

```ruby
# optional аргументы в конце
# плохо
def some_method(a = 1, b = 2, c, d)
  puts "#{a}, #{b}, #{c}, #{d}"
end

some_method('w', 'x')       # => '1, 2, w, x'
some_method('w', 'x', 'y')  # => 'w, 2, x, y' неожиданно!

# хорошо
def some_method(c, d, a = 1, b = 2)
  puts "#{a}, #{b}, #{c}, #{d}"
end
```

```ruby
# keyword arguments для boolean
# плохо
def some_method(bar = false)
  puts bar
end

# хорошо
def some_method(bar: false)
  puts bar
end

some_method            # => false
some_method(bar: true) # => true
```

```ruby
# keyword вместо optional
# плохо
def some_method(a, b = 5, c = 1)
end

# хорошо
def some_method(a, b: 5, c: 1)
end
```

```ruby
# arguments forwarding Ruby 2.7+
# плохо
def some_method(*args, **kwargs, &block)
  other_method(*args, **kwargs, &block)
end

# хорошо
def some_method(...)
  other_method(...)
end
```

```ruby
# block forwarding Ruby 3.1+
# плохо
def some_method(&block)
  other_method(&block)
end

# хорошо
def some_method(&)
  other_method(&)
end
```

```ruby
# endless methods Ruby 3.0+
# плохо
def fib(x) = if x < 2
  x
else
  fib(x - 1) + fib(x - 2)
end

# хорошо
def the_answer = 42
def get_x = @x
def square(x) = x * x
```

## Блоки

```ruby
# proc call shorthand
# плохо
names.map { |name| name.upcase }

# хорошо
names.map(&:upcase)
```

```ruby
# {} vs do...end
names = %w[Bozhidar Filipp Sarah]

# плохо
names.each do |name|
  puts name
end

# хорошо
names.each { |name| puts name }

# плохо - микс при chaining
names.select do |name|
  name.start_with?('S')
end.map { |name| name.upcase }

# хорошо
names.select { |name| name.start_with?('S') }.map(&:upcase)
```

```ruby
# explicit block argument
# плохо
def with_tmp_dir
  Dir.mktmpdir do |tmp_dir|
    Dir.chdir(tmp_dir) { |dir| yield dir }
  end
end

# хорошо
def with_tmp_dir(&block)
  Dir.mktmpdir do |tmp_dir|
    Dir.chdir(tmp_dir, &block)
  end
end
```

```ruby
# lambda синтаксис
# плохо - lambda для однострочника
l = lambda { |a, b| a + b }

# плохо - stabby для многострочника
l = ->(a, b) do
  tmp = a * 7
  tmp * b / 50
end

# хорошо - stabby для однострочника
l = ->(a, b) { a + b }

# хорошо - lambda для многострочника
l = lambda do |a, b|
  tmp = a * 7
  tmp * b / 50
end
```

```ruby
# proc вместо Proc.new
# плохо
p = Proc.new { |n| puts n }

# хорошо
p = proc { |n| puts n }
```

```ruby
# proc.call()
l = ->(v) { puts v }

# плохо
l[1]
l.(1)

# хорошо
l.call(1)
```

## Классы и модули

```ruby
# структура класса
class Person
  # 1. extend/include/prepend
  extend SomeModule
  include AnotherModule
  prepend YetAnotherModule

  # 2. inner classes
  class CustomError < StandardError
  end

  # 3. constants
  SOME_CONSTANT = 20

  # 4. attribute macros
  attr_reader :name

  # 5. other macros
  validates :name

  # 6. public class methods
  def self.some_method
  end

  # 7. initialize
  def initialize
  end

  # 8. public instance methods
  def some_method
  end

  # 9. protected и private в конце
  protected

  def some_protected_method
  end

  private

  def some_private_method
  end
end
```

```ruby
# mixins по отдельности
# плохо
class Person
  include Foo, Bar
end

# хорошо
class Person
  include Foo
  include Bar
end
```

```ruby
# explicit nesting для namespaces
module Utilities
  class Queue
  end
end

# плохо - проблемы с constant lookup
class Utilities::Store
  def initialize
    @queue = Queue.new  # найдёт ::Queue
  end
end

# хорошо
module Utilities
  class WaitingList
    def initialize
      @queue = Queue.new  # найдёт Utilities::Queue
    end
  end
end
```

```ruby
# modules вместо классов с class methods
# плохо
class SomeClass
  def self.some_method; end
  def self.some_other_method; end
end

# хорошо
module SomeModule
  module_function

  def some_method; end
  def some_other_method; end
end
```

```ruby
# module_function вместо extend self
# плохо
module Utilities
  extend self

  def parse_something(string)
  end
end

# хорошо
module Utilities
  module_function

  def parse_something(string)
  end
end
```

```ruby
# attr_reader вместо getter
# плохо
class Person
  def initialize(first_name, last_name)
    @first_name = first_name
    @last_name = last_name
  end

  def first_name
    @first_name
  end

  def last_name
    @last_name
  end
end

# хорошо
class Person
  attr_reader :first_name, :last_name

  def initialize(first_name, last_name)
    @first_name = first_name
    @last_name = last_name
  end
end
```

```ruby
# нет get_/set_
# плохо
class Person
  def get_name
    "#{@first_name} #{@last_name}"
  end

  def set_name(name)
    @first_name, @last_name = name.split(' ')
  end
end

# хорошо
class Person
  def name
    "#{@first_name} #{@last_name}"
  end

  def name=(name)
    @first_name, @last_name = name.split(' ')
  end
end
```

```ruby
# Struct.new
# хорошо
class Person
  attr_accessor :first_name, :last_name

  def initialize(first_name, last_name)
    @first_name = first_name
    @last_name = last_name
  end
end

# лучше
Person = Struct.new(:first_name, :last_name) do
end
```

```ruby
# duck typing вместо наследования
# плохо
class Animal
  def speak; end
end

class Duck < Animal
  def speak
    puts 'Quack! Quack'
  end
end

# хорошо
class Duck
  def speak
    puts 'Quack! Quack'
  end
end

class Dog
  def speak
    puts 'Bau! Bau!'
  end
end
```

```ruby
# нет class variables @@
class Parent
  @@class_var = 'parent'

  def self.print_class_var
    puts @@class_var
  end
end

class Child < Parent
  @@class_var = 'child'
end

Parent.print_class_var # => 'child' неожиданно!
# используй class instance variables
```

```ruby
# def self.method для class methods
class TestClass
  # плохо
  def TestClass.some_method; end

  # хорошо
  def self.some_method; end

  # тоже хорошо
  class << self
    def first_method; end
    def second_method; end
  end
end
```

## Коллекции

```ruby
# литералы
# плохо
arr = Array.new
hash = Hash.new

# хорошо
arr = []
hash = {}
```

```ruby
# %w и %i
STATES = %w[draft open closed]
ROLES = %i[admin moderator author]
```

```ruby
# first и last
# плохо
arr[0]
arr[-1]

# хорошо
arr.first
arr.last
```

```ruby
# символы как ключи
# плохо
hash = { 'one' => 1, 'two' => 2 }

# хорошо
hash = { one: 1, two: 2 }
```

```ruby
# Hash#key?
# плохо
hash.has_key?(:foo)
hash.has_value?(bar)

# хорошо
hash.key?(:foo)
hash.value?(bar)
```

```ruby
# Hash#fetch
heroes = { batman: 'Bruce Wayne', superman: 'Clark Kent' }

# плохо - nil если нет ключа
heroes[:batman]

# хорошо - exception если нет ключа
heroes.fetch(:batman)

# хорошо - с default
heroes.fetch(:supergirl, 'Kara Zor-El')

# хорошо - с блоком
heroes.fetch(:supergirl) { |key| "Unknown: #{key}" }
```

```ruby
# map/find/select/reduce
# плохо
result = []
items.each { |item| result << item.name }
result

# хорошо
items.map(&:name)
```

```ruby
# flat_map
# плохо
[[1, 2], [3, 4]].map { |arr| arr.map { |x| x * 2 } }.flatten

# хорошо
[[1, 2], [3, 4]].flat_map { |arr| arr.map { |x| x * 2 } }
```

```ruby
# reverse_each
# плохо
array.reverse.each { |item| puts item }

# хорошо
array.reverse_each { |item| puts item }
```

## Строки

```ruby
# интерполяция
# плохо
email_with_name = user.name + ' <' + user.email + '>'

# хорошо
email_with_name = "#{user.name} <#{user.email}>"
```

```ruby
# нет to_s в интерполяции
# плохо
"The answer is #{answer.to_s}"

# хорошо
"The answer is #{answer}"
```

```ruby
# heredoc Ruby 2.3+
code = <<~END
def test
  some_method
end
END
```

## Rails: Роутинг

```ruby
# плохо: custom actions
resources :cards do
  post :close
  post :reopen
  post :archive
end

# хорошо: отдельные ресурсы
resources :cards do
  resource :closure
  resource :goldness
  resource :pin
  resource :watch
  
  resources :assignments
  resources :comments do
    resources :reactions
  end
end
```

## Rails: Контроллеры

```ruby
# плохо: логика в контроллере
class Cards::ClosuresController < ApplicationController
  def create
    @card.transaction do
      @card.create_closure!(user: Current.user)
      @card.events.create!(action: :closed, creator: Current.user)
      @card.watchers.each do |w| 
        NotificationMailer.card_closed(w, @card).deliver_later
      end
    end
  end
end

# хорошо: контроллер оркестрирует
class Cards::ClosuresController < ApplicationController
  include CardScoped

  def create
    @card.close
    
    respond_to do |format|
      format.turbo_stream { render_card_replacement }
      format.json { head :no_content }
    end
  end
end
```

```ruby
# controller concern
module CardScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_card, :set_board
  end

  private
    def set_card
      @card = Current.user.accessible_cards.find_by!(number: params[:card_id])
    end

    def set_board
      @board = @card.board
    end

    def render_card_replacement
      render turbo_stream: turbo_stream.replace(
        [@card, :card_container],
        partial: "cards/container",
        method: :morph,
        locals: { card: @card.reload }
      )
    end
end
```

## Rails: Модели

```ruby
# модель с concerns
class Card < ApplicationRecord
  include Assignable, Closeable, Watchable, Taggable, Searchable
  
  belongs_to :account, default: -> { board.account }
  belongs_to :board
  belongs_to :creator, class_name: "User", default: -> { Current.user }

  has_many :comments, dependent: :destroy
end
```

```ruby
# concern - самодостаточное поведение
module Card::Closeable
  extend ActiveSupport::Concern

  included do
    has_one :closure, dependent: :destroy

    scope :closed, -> { joins(:closure) }
    scope :open, -> { where.missing(:closure) }
  end

  def closed?
    closure.present?
  end

  def close(user: Current.user)
    unless closed?
      transaction do
        create_closure!(user: user)
        track_event :closed, creator: user
      end
    end
  end

  def reopen(user: Current.user)
    if closed?
      transaction do
        closure&.destroy
        track_event :reopened, creator: user
      end
    end
  end
end
```

```ruby
# состояние как записи
# плохо: boolean колонка
class Card < ApplicationRecord
  scope :closed, -> { where(closed: true) }
end

# хорошо: отдельная таблица
class Closure < ApplicationRecord
  belongs_to :card, touch: true
  belongs_to :user, optional: true
end

class Card < ApplicationRecord
  has_one :closure, dependent: :destroy

  scope :closed, -> { joins(:closure) }
  scope :open, -> { where.missing(:closure) }

  def closed?
    closure.present?
  end
end
```

```ruby
# Current для контекста
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :identity, :account
  attribute :request_id, :user_agent, :ip_address
end

# использование
class Card < ApplicationRecord
  belongs_to :creator, class_name: "User", default: -> { Current.user }
  belongs_to :account, default: -> { board.account }
end
```

```ruby
# нет service objects
# плохо
class CloseCardService
  def initialize(card, user)
    @card = card
    @user = user
  end

  def call
    @card.transaction do
      @card.create_closure!(user: @user)
      @card.track_event(:closed)
    end
  end
end

# хорошо
class Card < ApplicationRecord
  def close(user: Current.user)
    transaction do
      create_closure!(user: user)
      track_event :closed, creator: user
    end
  end
end
```

```ruby
# scope naming
scope :chronologically,         -> { order created_at: :asc }
scope :reverse_chronologically, -> { order created_at: :desc }
scope :alphabetically,          -> { order name: :asc }
scope :latest,                  -> { order last_active_at: :desc }

scope :preloaded, -> {
  preload(:creator, :assignees, :column, :tags)
    .with_rich_text_description_and_embeds
}

scope :sorted_by, ->(sort) do
  case sort.to_s
  when "latest" then latest
  when "oldest" then chronologically
  else latest
  end
end
```

## Rails: Jobs

```ruby
# тонкие jobs
class NotifyRecipientsJob < ApplicationJob
  def perform(notifiable)
    notifiable.notify_recipients
  end
end

# конвенция _later и _now
module Card::Readable
  def mark_as_read_later(user:)
    MarkCardAsReadJob.perform_later(self, user)
  end

  def mark_as_read_now(user:)
    readings.find_or_create_by!(user: user).touch
  end
end
```

## Rails: Тесты

```ruby
# Minitest + fixtures
class CardTest < ActiveSupport::TestCase
  setup do
    Current.session = sessions(:david)
  end

  test "closed scope returns only closed cards" do
    assert_equal [cards(:shipping)], Card.closed
  end
  
  test "close creates closure record" do
    card = cards(:logo)
    
    assert_changes -> { card.reload.closed? }, from: false, to: true do
      card.close
    end
  end
end
```

```yaml
# fixtures
# test/fixtures/cards.yml
logo:
  account: 37s
  board: writebook
  creator: david
  title: "Logo Design"
  number: 1

shipping:
  account: 37s
  board: writebook  
  creator: david
  title: "Shipping"
  number: 2
```

## Rails: HTTP Caching

```ruby
class Cards::AssignmentsController < ApplicationController
  def new
    @users = @board.users.active
    fresh_when etag: [@users, @card.assignees]
  end
end

class ApplicationController < ActionController::Base
  etag { "v1" }
end
```
