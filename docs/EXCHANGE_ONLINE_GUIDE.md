# Повний посібник: PowerShell Core на Ubuntu, підключення до Exchange Online та налаштування Application Access Policy (RBAC)

Цей документ об'єднує всі кроки для встановлення PowerShell на Ubuntu, авторизації в Exchange Online (Microsoft 365), створення Mail-Enabled Security Group, додавання користувачів та обмеження прав додатків через `ApplicationAccessPolicy`.

---

## Крок 1: Встановлення PowerShell Core (`pwsh`) на Ubuntu

Виконайте наступні команди в терміналі Ubuntu для додавання репозиторію Microsoft та встановлення PowerShell:

```bash
# 1. Оновлення списку пакетів та встановлення залежностей
sudo apt-get update
sudo apt-get install -y wget apt-transport-https software-properties-common

# 2. Завантаження та реєстрація ключа репозиторію Microsoft
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

# 3. Встановлення PowerShell
sudo apt-get update
sudo apt-get install -y powershell
```

**Альтернативний спосіб встановлення через Snap:**

```bash
sudo snap install powershell --classic
```

---

## Крок 2: Запуск PowerShell та встановлення модуля Exchange Online

Запустіть інтерактивну сесію PowerShell:

```bash
pwsh
```

Усередині сесії PowerShell виконайте завантаження та встановлення офіційного модуля `ExchangeOnlineManagement`:

```powershell
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Repository PSGallery -Force
```

---

## Крок 3: Підключення (авторизація) до Exchange Online

### Спосіб А: Через Device Code (рекомендовано для Linux / SSH)

Виконайте команду з прапорцем `-Device`:

```powershell
Connect-ExchangeOnline -UserPrincipalName admin@yourdomain.edu.ua -Device
```

PowerShell виведе посилання (`https://microsoft.com/devicelogin`) та 9-значний код (наприклад, `G8XYZ123`).

1. Відкрийте посилання у вашому звичайному веббраузері.
2. Введіть код, авторизуйтеся під обліковим записом адміністратора M365 та підтвердьте MFA (якщо увімкнено).
3. Після підтвердження термінал в Ubuntu автоматично завершить авторизацію.

### Спосіб Б: Через Certificate-based Auth (для скриптів без участі людини)

```powershell
Connect-ExchangeOnline `
  -CertificateFilePath "/absolute/path/to/cert.pem" `
  -CertificatePassword (ConvertTo-SecureString "" -AsPlainText -Force) `
  -AppId "<AZURE_CLIENT_ID>" `
  -Organization "yourtenant.onmicrosoft.com"
```

Перевірте успішність підключення:

```powershell
Get-OrganizationConfig | Select-Object Name, Identity
```

---

## Крок 4: Створення групи безпеки (Mail-Enabled Security Group)

Для того, щоб прив'язати політику доступу додатка (`ApplicationAccessPolicy`) до конкретних скриньок, спочатку необхідно створити групу безпеки типу `Security`:

```powershell
New-DistributionGroup -Name "SMTP2Graph-Allowed-Senders" -Type "Security"
```

> **Примітка:** Зачекайте 1–2 хвилини після створення групи, щоб об'єкт реплікувався у службі каталогів Exchange.

Перевірити наявність створеної групи можна командою:

```powershell
Get-DistributionGroup -Identity "SMTP2Graph-Allowed-Senders"
```

---

## Крок 5: Додавання та перевірка дозволених користувачів (скриньок)

Додайте першу та всі наступні дозволені скриньки до створеної групи:

```powershell
# Додавання основної скриньки відправника
Add-DistributionGroupMember -Identity "SMTP2Graph-Allowed-Senders" -Member "noreply@ldubgd.edu.ua"

# Додавання додаткових дозволених скриньок (за потреби)
Add-DistributionGroupMember -Identity "SMTP2Graph-Allowed-Senders" -Member "alerts@ldubgd.edu.ua"
Add-DistributionGroupMember -Identity "SMTP2Graph-Allowed-Senders" -Member "support@ldubgd.edu.ua"
```

Перевірте список учасників групи:

```powershell
Get-DistributionGroupMember -Identity "SMTP2Graph-Allowed-Senders" | Select-Object Name, PrimarySmtpAddress
```

---

## Крок 6: Створення та тестування ApplicationAccessPolicy (RBAC)

### 6.1. Створення політики обмеження доступу додатка

Створіть політику, яка обмежує доступ додатку (App Registration) лише членами групи `SMTP2Graph-Allowed-Senders`:

```powershell
New-ApplicationAccessPolicy `
  -AppId "<AZURE_CLIENT_ID>" `
  -PolicyScopeGroupId "SMTP2Graph-Allowed-Senders" `
  -AccessRight RestrictAccess `
  -Description "Restrict SMTP2Graph to specific sender mailboxes only."
```

> Замініть `<AZURE_CLIENT_ID>` на Application ID вашої реєстрації в Entra ID.

### 6.2. Перевірка списку наявних політик

```powershell
Get-ApplicationAccessPolicy
```

### 6.3. Перевірка роботи політики (Positive та Negative Tests)

Виконайте перевірку прямо у PowerShell для кожної потрібної скриньки:

```powershell
# 1. Дозволені скриньки (члени групи) -> Очікується: Granted
Test-ApplicationAccessPolicy -AppId "<AZURE_CLIENT_ID>" -Identity "noreply@ldubgd.edu.ua"
Test-ApplicationAccessPolicy -AppId "<AZURE_CLIENT_ID>" -Identity "alerts@ldubgd.edu.ua"

# 2. Заблокована скринька (поза групою) -> Очікується: Denied
Test-ApplicationAccessPolicy -AppId "<AZURE_CLIENT_ID>" -Identity "denied-user@ldubgd.edu.ua"
```

> **Важливо (Propagation Delay):** Повне застосування та розповсюдження `ApplicationAccessPolicy` в інфраструктурі Microsoft 365 може займати від **15 до 30 хвилин**.

---

## Крок 7: Завершення сесії PowerShell

Після завершення всіх адміністративних робіт обов'язково закрийте сесію Exchange Online:

```powershell
Disconnect-ExchangeOnline -Confirm:$false
exit
```
