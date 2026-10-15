# Enable Google sign-in

The application code and Supabase database are already connected. The project owner must complete this one-time setup because Google requires the owner to create and consent to OAuth credentials. Do not put the Google client secret in the Android app or this repository.

No APK rebuild is needed after these settings are saved.

## 1. Create a Google OAuth client

1. Open [Google Cloud Console](https://console.cloud.google.com/).
2. Create or select a project.
3. Open **Google Auth Platform** and complete the branding/consent screen. For testing, add your own Google email as a test user.
4. Open **Clients → Create client**.
5. Choose **Web application**.
6. Add this authorized redirect URI exactly:

   ```text
   https://opdrhpyooeeafluuzdgm.supabase.co/auth/v1/callback
   ```

7. Save, then copy the **Client ID** and **Client secret**. Treat the secret like a password.

## 2. Enable Google in Supabase

1. Open the [Supabase Google provider page](https://supabase.com/dashboard/project/opdrhpyooeeafluuzdgm/auth/providers).
2. Select **Google**, turn it on, and paste the Google Client ID and Client secret.
3. Save.

## 3. Allow the Android callback

1. Open [Supabase URL Configuration](https://supabase.com/dashboard/project/opdrhpyooeeafluuzdgm/auth/url-configuration).
2. Under **Redirect URLs**, add this exact value:

   ```text
   nurzikr://auth/callback
   ```

3. Save.

## 4. Test

1. Install the latest APK from the repository release.
2. Open **Options → Sign in**.
3. Choose the Google account configured as a test user.
4. Return to Nūr Zikr. The Options page should show the account name and **Progress backed up**.
5. Make a few direct taps and open **Compete** to check the global leaderboard.

If Google says the app is blocked, confirm that the account is listed as a test user while the consent screen is in testing mode. If Supabase reports an invalid redirect, check both redirect addresses character-for-character.
