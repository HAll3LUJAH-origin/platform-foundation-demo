# Runbook — orders-api

Справочник дежурного по алертам из `helm/orders-api/templates/prometheusrule.yaml`. У каждого алерта `runbook_url` ведёт на соответствующую секцию ниже.

`NS` = `orders-api-dev` или `orders-api-stage`. В stage high error rate и target-down пейджат (critical). Задержка и нехватка реплик предупреждают везде.

Первый вопрос всегда один: **был ли деплой за последние 30 минут?** Если да — откатиться сначала, разбираться потом. Почти всегда это именно деплой.

---

## High 5xx error rate

`OrdersApiHighErrorRate` срабатывает, когда больше 5% запросов отдают 5xx пять минут подряд при реальном трафике.

Подтвердить масштаб:

```bash
kubectl -n $NS get deploy,po
# доля ошибок сейчас — в Prometheus или панели "Error ratio" в Grafana:
#   sum(rate(http_requests_total{namespace="$NS",status=~"5.."}[5m]))
#   / sum(rate(http_requests_total{namespace="$NS"}[5m]))
```

Проверить, не совпадает ли с недавним изменением:

```bash
kubectl -n $NS rollout history deploy/orders-api
helm -n $NS history orders-api
kubectl -n $NS get events --sort-by=.lastTimestamp | tail -20
```

Запущенная сборка — в `app_build_info{namespace="$NS"}`. Всплеск совпадает с версией — откатиться и разбираться после. Не нужно тратить время на диагностику плохого деплоя, когда можно просто откатить.

Триаж подов:

```bash
kubectl -n $NS get po -o wide
kubectl -n $NS logs deploy/orders-api --tail=100
kubectl -n $NS describe po <pod>     # OOMKilled? CrashLoopBackOff? провал проб?
kubectl -n $NS top po                # CPU/память vs лимиты
```

Что обычно находишь:

- **Плохой релиз** — ошибки начинаются ровно с момента деплоя. Логи показывают падение нового кода. Откатить.
- **OOMKilled** — describe показывает причину, счётчик рестартов растёт. Поднять лимит памяти или починить утечку.
- **Зависимость упала** — в логах таймауты, ошибки не коррелируют с деплоем. Эскалировать владельцу.
- **Перегрузка** — CPU у лимита, задержка тоже алертит, HPA на максимуме.

Смягчение:

```bash
# плохой релиз
helm -n $NS rollback orders-api
kubectl -n $NS rollout status deploy/orders-api

# OOM / давление по ресурсам — масштабировать пока идёт фикс
kubectl -n $NS scale deploy/orders-api --replicas=N

# перегрузка — проверить HPA, поднять maxReplicas если упёрся
kubectl -n $NS get hpa
```

При падении зависимости — эскалировать владельцу. Рассмотреть сброс нагрузки.

Восстановление: доля ошибок ниже 5% и стабильна пять минут — алерт гаснет. Подтвердить: `kubectl -n $NS get po`, все Ready, рестарты не растут.

Короткая заметка по инциденту: триггер, масштаб, причина, фикс, follow-up'ы. Если это был плохой релиз — что поймало бы его раньше?

---

## High latency

`OrdersApiHighLatencyP99` — p99 выше 500ms десять минут подряд.

Сервис жив, но тормозит:

```bash
kubectl -n $NS top po       # насыщение CPU?
kubectl -n $NS get hpa      # масштабировался? упёрся в максимум?
```

CPU у лимита + HPA на максимуме → поднять `maxReplicas` или лимит CPU. Задержка без давления по CPU — скорее медленная зависимость или борьба за блокировки. Смотреть логи и downstream-задержку, проверить коррелирующий деплой:

```bash
helm -n $NS history orders-api
```

Совпадает — откатить. Нет — масштабировать и чинить downstream.

---

## Target down

`OrdersApiTargetDown` — Prometheus не может скрейпить сервис две минуты. Процесс скорее всего падает, ловит OOM или недоступен.

```bash
kubectl -n $NS get po
kubectl -n $NS describe po <pod>      # последнее состояние, причина
kubectl -n $NS logs <pod> --previous  # crash-логи предыдущего контейнера
```

CrashLoopBackOff после деплоя → откатить. Все поды Pending → проверить ноды и квоту: `kubectl -n $NS describe quota`, `kubectl get nodes`. Поды Running, но не скрейпятся → скорее несовпадение меток ServiceMonitor или NetworkPolicy блокирует namespace мониторинга; проверить, что метка `monitoring` существует.

---

## Not enough ready replicas

`OrdersApiNotEnoughReadyReplicas` — доступных реплик меньше желаемого десять минут. Ёмкость деградировала, даже если выжившие поды обслуживают нормально.

```bash
kubectl -n $NS get deploy orders-api
kubectl -n $NS get po
kubectl -n $NS describe po <pod>
```

Pending / FailedScheduling → квота исчерпана или нет места на нодах (`kubectl -n $NS describe quota`). Провал readiness → приложение не проходит `/readyz`; смотреть логи и конфиг readiness в `values-<env>.yaml`. CrashLooping → см. *Target down*.

---

## Эскалация

1. Дежурный инженер (этот runbook).
2. Владелец сервиса / канал платформенной команды.
3. При падении зависимости — команда, которая её владеет.

Писать в канал инцидента при ack, при смягчении и при закрытии.
