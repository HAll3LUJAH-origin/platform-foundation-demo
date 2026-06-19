# Секреты и базовая безопасность

## Нет секретов в git

Рантайм-конфиг приложения нечувствительный, лежит в ConfigMap — `PORT`, `WARMUP`, `DEBUG_ENDPOINTS`, `ENVIRONMENT`. Ничего чувствительного не коммитится.

`.gitignore` блокирует state Terraform (`*.tfstate*`, который может содержать токен деплойщика), `*.tfvars`, kubeconfig'и и `.env*`.

Настоящие секреты приходят извне репозитория. В CI — GitHub Environment secrets, ограниченные по env: `KUBE_SERVER`, `KUBE_CA_DATA`, `KUBE_DEPLOYER_TOKEN`. Секреты dev невидимы для джоб stage.

Для секретов приложения в кластере — SOPS-зашифрованные файлы (коммитим шифротекст, расшифровываем в CI ключом KMS) или External Secrets Operator из AWS Secrets Manager, Vault или GCP Secret Manager. Чарт потребляет секреты через `envFrom`/`secretRef` — значения никогда не шаблонизируются.

Pre-commit хук `gitleaks` или `trufflehog` плюс шаг секрет-скана в CI. Поймать случайный коммит локально намного дешевле, чем ротировать утёкший токен.

## Сетевая политика

Два слоя. Сначала default-deny.

Базис namespace (Terraform) — NetworkPolicy `default-deny-all` блокирует весь ingress и egress, затем минимальные allow'ы: egress DNS в `kube-system` на UDP/TCP 53 и ingress под-в-под внутри того же namespace.

Поверх этого Helm-чарт добавляет точечную политику: порт приложения принимает ingress только от `ingress-nginx`, а `/metrics` — только от namespace `monitoring`.

Всё. Под резолвит DNS и общается внутри своего namespace. Ingress-контроллер достаёт до приложения. Prometheus скрейпит. Больше внутрь ничего не проходит. Добавить зависимость — добавить один явный allow.

## Allowlist вебхуков

Для входящих вебхуков (платёжный провайдер, VCS, всё что нас зовёт):

1. **Сначала проверить подпись.** Валидировать HMAC провайдера над сырым телом с секретом из хранилища и проверять timestamp для отбраковки replay'ев. Запрос не прошедший проверку отбрасывается до любой бизнес-логики.
2. **Source-IP allowlist на краю.** Ограничить путь вебхука опубликованными провайдером egress-CIDR'ами через аннотации ingress (`nginx.ingress.kubernetes.io/whitelist-source-range`) или облачный LB/WAF. Список CIDR в конфиге — изменения через PR-ревью.
3. **NetworkPolicy на получателя.** Поды-обработчики принимают ingress только от ingress-контроллера.

IP-allowlist сужает поверхность, но из-за спуфинга и дрейфа CIDR проверка подписи — основной контроль. Allowlist это подкрепление, не главный гейт.

## Харденинг нагрузки

Задано в `values.yaml`, не ослабляется по env, принуждается Kyverno: `runAsNonRoot`, uid 65532, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, все capabilities сброшены, `seccompProfile: RuntimeDefault`, `automountServiceAccountToken: false`, distroless-образ без shell.
