# Ayije CDM Architecture Patterns — Knowledge Base

> 분석 기준: `Ayije_CDM_ v3.60` (WoW 12.0.1 Retail)
> 목적: DDingUI CDM 최적화 시 참조 기준 패턴 문서

## 파일 목록

| 파일 | 내용 |
|------|------|
| `01_update_queue.md` | 단일 Updater + QueueProcessor 패턴 |
| `02_event_pipeline.md` | 이벤트 → 갱신 파이프라인 (C_Timer 없음) |
| `03_cache_patterns.md` | 캐시 우선 조회 패턴 (spellIDCache, styleCacheVersion) |
| `04_taint_safety.md` | Taint 방어 패턴 (weak-meta, 전투 중 큐잉) |
| `05_cooldown_watcher.md` | TrackerCooldownWatcher 이벤트 기반 쿨다운 추적 |
