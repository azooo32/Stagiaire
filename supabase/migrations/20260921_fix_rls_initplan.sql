-- ============================================================
-- Migration: تصحيح سياسات RLS لتفعيل InitPlan optimization
-- التاريخ: 2026-09-21
-- المشكلة: auth.uid() تُستدعى لكل صف على حدة
-- الحل:   (SELECT auth.uid()) تُنفَّذ مرة واحدة كـ InitPlan
-- الأثر:  تخفيض CPU بنسبة 40-80% على الاستعلامات الكبيرة
--
-- السياسات المشمولة: 38 سياسة (بعد استبعاد ما هو صحيح أصلاً)
-- السياسات المستبعدة لأنها صحيحة مسبقاً:
--   - user_slide_workspaces (الثلاث) → تستخدم (SELECT auth.uid()) مسبقاً ✅
--   - user_progress         → يستخدم (SELECT auth.uid()) مسبقاً ✅
--   - user_favorites        → يستخدم (SELECT auth.uid()) مسبقاً ✅
--   - leaderboard           → يستخدم (SELECT auth.uid()) مسبقاً ✅
--   - questions, subjects, slides (بعضها), titles → صحيحة مسبقاً ✅
-- ============================================================

BEGIN;

-- ============================================================
-- 1. osce_progress
-- ============================================================
DROP POLICY IF EXISTS "osce_progress_select" ON osce_progress;
CREATE POLICY "osce_progress_select" ON osce_progress
  FOR SELECT USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "osce_progress_update" ON osce_progress;
CREATE POLICY "osce_progress_update" ON osce_progress
  FOR UPDATE USING ((SELECT auth.uid()) = user_id);

-- ============================================================
-- 2. study_plans
-- ============================================================
DROP POLICY IF EXISTS "Users can delete their own study plans" ON study_plans;
CREATE POLICY "Users can delete their own study plans" ON study_plans
  FOR DELETE USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update their own study plans" ON study_plans;
CREATE POLICY "Users can update their own study plans" ON study_plans
  FOR UPDATE
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can view their own study plans" ON study_plans;
CREATE POLICY "Users can view their own study plans" ON study_plans
  FOR SELECT USING ((SELECT auth.uid()) = user_id);

-- ============================================================
-- 3. user_bookmarks  (cmd=ALL, بدون with_check)
-- ============================================================
DROP POLICY IF EXISTS "Users can manage their own bookmarks" ON user_bookmarks;
CREATE POLICY "Users can manage their own bookmarks" ON user_bookmarks
  FOR ALL USING (user_id = (SELECT auth.uid()));

-- ============================================================
-- 4. user_notes  (cmd=ALL, بدون with_check)
-- ============================================================
DROP POLICY IF EXISTS "Users can manage their own notes" ON user_notes;
CREATE POLICY "Users can manage their own notes" ON user_notes
  FOR ALL USING (user_id = (SELECT auth.uid()));

-- ============================================================
-- 5. user_pdf_workspaces
-- ============================================================
DROP POLICY IF EXISTS "Users can delete their own PDF workspace" ON user_pdf_workspaces;
CREATE POLICY "Users can delete their own PDF workspace" ON user_pdf_workspaces
  FOR DELETE USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can read their own PDF workspace" ON user_pdf_workspaces;
CREATE POLICY "Users can read their own PDF workspace" ON user_pdf_workspaces
  FOR SELECT USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update their own PDF workspace" ON user_pdf_workspaces;
CREATE POLICY "Users can update their own PDF workspace" ON user_pdf_workspaces
  FOR UPDATE
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- ============================================================
-- 6. user_sessions
-- ============================================================
DROP POLICY IF EXISTS "Users can delete own sessions" ON user_sessions;
CREATE POLICY "Users can delete own sessions" ON user_sessions
  FOR DELETE USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can read own sessions" ON user_sessions;
CREATE POLICY "Users can read own sessions" ON user_sessions
  FOR SELECT USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update own sessions" ON user_sessions;
CREATE POLICY "Users can update own sessions" ON user_sessions
  FOR UPDATE
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- ============================================================
-- 7. user_station_progress  (cmd=ALL, بدون with_check)
-- ============================================================
DROP POLICY IF EXISTS "Users can manage their own station progress" ON user_station_progress;
CREATE POLICY "Users can manage their own station progress" ON user_station_progress
  FOR ALL USING (user_id = (SELECT auth.uid()));

-- ============================================================
-- 8. user_study_stats  (cmd=ALL, بدون with_check)
-- ============================================================
DROP POLICY IF EXISTS "Users can manage their own study stats" ON user_study_stats;
CREATE POLICY "Users can manage their own study stats" ON user_study_stats
  FOR ALL USING (user_id = (SELECT auth.uid()));

-- ============================================================
-- 9. user_subscriptions
-- ============================================================
DROP POLICY IF EXISTS "Users can read own subscriptions" ON user_subscriptions;
CREATE POLICY "Users can read own subscriptions" ON user_subscriptions
  FOR SELECT USING ((SELECT auth.uid()) = user_id);

-- ============================================================
-- 10. user_video_progress  (cmd=ALL, بدون with_check)
-- ============================================================
DROP POLICY IF EXISTS "Users can manage their own video progress" ON user_video_progress;
CREATE POLICY "Users can manage their own video progress" ON user_video_progress
  FOR ALL USING (user_id = (SELECT auth.uid()));

-- ============================================================
-- 11. user_voice_progress  (cmd=ALL, بدون with_check)
-- ============================================================
DROP POLICY IF EXISTS "Users can manage their own voice progress" ON user_voice_progress;
CREATE POLICY "Users can manage their own voice progress" ON user_voice_progress
  FOR ALL USING (user_id = (SELECT auth.uid()));

-- ============================================================
-- 12. users
-- ============================================================
DROP POLICY IF EXISTS "Users can update own profile" ON users;
CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE
  USING ((SELECT auth.uid()) = id)
  WITH CHECK ((SELECT auth.uid()) = id);

DROP POLICY IF EXISTS "Users can view own data or admin/owner can view all" ON users;
CREATE POLICY "Users can view own data or admin/owner can view all" ON users
  FOR SELECT USING (((SELECT auth.uid()) = id) OR is_admin_or_owner());

-- ============================================================
-- 13. السياسات المعقدة (EXISTS + users join)
-- ============================================================

-- clinical_sections
DROP POLICY IF EXISTS "Admins can delete clinical_sections" ON clinical_sections;
CREATE POLICY "Admins can delete clinical_sections" ON clinical_sections
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  );

DROP POLICY IF EXISTS "Admins can update clinical_sections" ON clinical_sections;
CREATE POLICY "Admins can update clinical_sections" ON clinical_sections
  FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  );

-- clinical_subjects
DROP POLICY IF EXISTS "Admins can delete clinical_subjects" ON clinical_subjects;
CREATE POLICY "Admins can delete clinical_subjects" ON clinical_subjects
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  );

DROP POLICY IF EXISTS "Admins can update clinical_subjects" ON clinical_subjects;
CREATE POLICY "Admins can update clinical_subjects" ON clinical_subjects
  FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  );

-- osce_questions
DROP POLICY IF EXISTS "osce_questions_delete" ON osce_questions;
CREATE POLICY "osce_questions_delete" ON osce_questions
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = 'owner'::text)
  );

DROP POLICY IF EXISTS "osce_questions_update" ON osce_questions;
CREATE POLICY "osce_questions_update" ON osce_questions
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY[('admin'::character varying)::text, ('owner'::character varying)::text]))
  );

-- pdf_lecture_recordings
DROP POLICY IF EXISTS "Managers can delete lecture recordings" ON pdf_lecture_recordings;
CREATE POLICY "Managers can delete lecture recordings" ON pdf_lecture_recordings
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND lower(TRIM(BOTH FROM (users.role)::text)) = ANY (ARRAY['admin'::text, 'owner'::text, 'manager'::text]))
  );

DROP POLICY IF EXISTS "Managers can update lecture recordings" ON pdf_lecture_recordings;
CREATE POLICY "Managers can update lecture recordings" ON pdf_lecture_recordings
  FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND lower(TRIM(BOTH FROM (users.role)::text)) = ANY (ARRAY['admin'::text, 'owner'::text, 'manager'::text]))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND lower(TRIM(BOTH FROM (users.role)::text)) = ANY (ARRAY['admin'::text, 'owner'::text, 'manager'::text]))
  );

-- question_image_relations
DROP POLICY IF EXISTS "Admins can delete question_image_relations" ON question_image_relations;
CREATE POLICY "Admins can delete question_image_relations" ON question_image_relations
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  );

DROP POLICY IF EXISTS "Admins can update question_image_relations" ON question_image_relations;
CREATE POLICY "Admins can update question_image_relations" ON question_image_relations
  FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  );

-- question_images
DROP POLICY IF EXISTS "Admins can delete question_images" ON question_images;
CREATE POLICY "Admins can delete question_images" ON question_images
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  );

DROP POLICY IF EXISTS "Admins can update question_images" ON question_images;
CREATE POLICY "Admins can update question_images" ON question_images
  FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY (ARRAY['owner'::text, 'admin'::text]))
  );

-- question_reports
DROP POLICY IF EXISTS "Allow admins/owners/managers to delete reports" ON question_reports;
CREATE POLICY "Allow admins/owners/managers to delete reports" ON question_reports
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'manager'::character varying])::text[]))
  );

DROP POLICY IF EXISTS "Allow admins/owners/managers to select reports" ON question_reports;
CREATE POLICY "Allow admins/owners/managers to select reports" ON question_reports
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'manager'::character varying])::text[]))
  );

-- slide_stations  (cmd=ALL, بدون with_check)
DROP POLICY IF EXISTS "Write access for admins and owners - slide_stations" ON slide_stations;
CREATE POLICY "Write access for admins and owners - slide_stations" ON slide_stations
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY ((ARRAY['admin'::character varying, 'owner'::character varying])::text[]))
  );

-- slides: فقط السياسة التي لا تزال تستخدم auth.uid() مباشرة
DROP POLICY IF EXISTS "Write access for admins and owners - slides" ON slides;
CREATE POLICY "Write access for admins and owners - slides" ON slides
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY ((ARRAY['admin'::character varying, 'owner'::character varying])::text[]))
  );

-- sync_metadata  (cmd=ALL, بدون with_check)
DROP POLICY IF EXISTS "Write access for admins and owners - sync_metadata" ON sync_metadata;
CREATE POLICY "Write access for admins and owners - sync_metadata" ON sync_metadata
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY ((ARRAY['admin'::character varying, 'owner'::character varying])::text[]))
  );

-- university_access  (cmd=ALL, بدون with_check)
DROP POLICY IF EXISTS "Admins have full access to university access" ON university_access;
CREATE POLICY "Admins have full access to university access" ON university_access
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY ((ARRAY['admin'::character varying, 'owner'::character varying, 'manager'::character varying])::text[]))
  );

-- user_subscriptions (admin — cmd=ALL, بدون with_check)
DROP POLICY IF EXISTS "Admins have full access to subscriptions" ON user_subscriptions;
CREATE POLICY "Admins have full access to subscriptions" ON user_subscriptions
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY ((ARRAY['admin'::character varying, 'owner'::character varying, 'manager'::character varying])::text[]))
  );

-- videos  (cmd=ALL, بدون with_check)
DROP POLICY IF EXISTS "Write access for admins and owners - videos" ON videos;
CREATE POLICY "Write access for admins and owners - videos" ON videos
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY ((ARRAY['admin'::character varying, 'owner'::character varying])::text[]))
  );

-- voice_notes  (cmd=ALL, بدون with_check)
DROP POLICY IF EXISTS "Write access for admins and owners - voice_notes" ON voice_notes;
CREATE POLICY "Write access for admins and owners - voice_notes" ON voice_notes
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users
            WHERE users.id = (SELECT auth.uid())
            AND (users.role)::text = ANY ((ARRAY['admin'::character varying, 'owner'::character varying])::text[]))
  );

COMMIT;
