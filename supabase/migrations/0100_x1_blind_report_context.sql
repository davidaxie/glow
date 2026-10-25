-- 0100_x1_blind_report_context.sql · X1 · Blind mode
--
-- Reports made from a Blind chat go into Glow's public.reports with context 'blind_chat' and
-- context_id = the blind chat ID (docs/briefs/blind-mode.md, decision 4). An enum value can't be
-- used in the transaction that adds it, so it gets its own migration, before 0101.

alter type public.report_context add value if not exists 'blind_chat';
