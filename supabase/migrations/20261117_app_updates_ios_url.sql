-- Migration: App Store link for iOS updates
-- Fill ios_url (the App Store link) on a release row once that build is live
-- on the App Store. iOS shows the update dialog for the newest row that has
-- ios_url and a version_code higher than the installed build number; the
-- update button opens that link.
-- Android keeps using apk_url (a direct .apk download, or a Google Play link).

ALTER TABLE public.app_updates
  ADD COLUMN IF NOT EXISTS ios_url TEXT;

-- An iOS-only release has no APK.
ALTER TABLE public.app_updates
  ALTER COLUMN apk_url DROP NOT NULL;

COMMENT ON COLUMN public.app_updates.ios_url IS
  'App Store link. Set it when this build is live on the App Store.';
