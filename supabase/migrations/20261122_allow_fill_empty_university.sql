-- Allow a student/admin to FILL an empty university once (complete-profile
-- step for new Google accounts and old accounts that skipped it), while a
-- university that is already set can still be changed by the owner only.
--
-- Same function as the live version (read 2026-11-22); only the university
-- block changed: the owner check now applies only when OLD.university is set.

CREATE OR REPLACE FUNCTION public.protect_user_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL
       OR current_user IN ('postgres', 'supabase_admin', 'service_role')
       OR (NULLIF(current_setting('request.jwt.claim.role', true), '') = 'service_role') THEN
        RETURN NEW;
    END IF;

    IF NEW.role IS DISTINCT FROM OLD.role THEN
        IF NOT is_owner() THEN
            RAISE EXCEPTION 'غير مصرح: تعديل رتب المشرفين وصلاحية الأدمن مخصصة لمالك المنصة (Owner) فقط';
        END IF;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF NOT is_admin_or_owner() THEN
            RAISE EXCEPTION 'غير مصرح: ليس لديك صلاحية تعديل حالة المستخدم';
        END IF;
    END IF;

    IF NEW.email IS DISTINCT FROM OLD.email THEN
        IF NOT is_owner() THEN
            RAISE EXCEPTION 'غير مصرح: تعديل البريد الإلكتروني مخصص للمالك فقط';
        END IF;
    END IF;

    -- [تغيير الجامعة university]: مسموح فقط للمالك، ومن لوحة التحكم فقط
    -- استثناء: إذا كانت الجامعة فارغة يُسمح للطالب بتعبئتها مرة واحدة فقط
    IF NEW.university IS DISTINCT FROM OLD.university THEN
        IF NOT is_owner() AND COALESCE(BTRIM(OLD.university), '') <> '' THEN
            RAISE EXCEPTION 'غير مصرح: تعديل الجامعة مخصص لمالك المنصة فقط';
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;
