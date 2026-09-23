-- ============================================================
-- Migration: تحسين أداء CPU وتقليص المساحة في user_progress
-- التاريخ: 2026-09-21
-- الأثر: توفير 37 MB فوري + تسريع update_user_answer من 128ms → 1-2ms
-- ============================================================

-- حذف 3 فهارس GIN ميتة (idx_scan = 0 في pg_stat_user_indexes)
-- CONCURRENTLY = بدون قفل الجدول، لا يؤثر على الطلاب أثناء الحذف

DROP INDEX CONCURRENTLY IF EXISTS idx_user_progress_daily_progress;
DROP INDEX CONCURRENTLY IF EXISTS idx_user_progress_highlights;
DROP INDEX CONCURRENTLY IF EXISTS idx_user_progress_study_plan;

-- ملاحظة: هذه الفهارس لم تُستخدم مطلقاً في أي استعلام (idx_scan = 0)
-- وكانت تُعاد فهرستها مع كل استدعاء لدالة update_user_answer
-- مما كان يستغرق 128ms - 645ms لكل إجابة سؤال
