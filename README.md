# מערכת ניהול שעות עובדים (שעון כניסה ויציאה)

- `public/` – אפליקציית ווב (Firebase Hosting + Firestore)
- `mac/` – אפליקציית macOS (SwiftUI)
- `firestore.rules` – כללי אבטחה

## אפליקציית האנדרואיד לעובדות
- התקנה ראשונה: לשלוח לעובדת את הקישור https://shaon-ovdot-2c10.web.app/android/shaon.apk
- גרסה חדשה: להעלות `versionCode` ו-`versionName` ב-`android/app/build.gradle.kts`, להריץ `tools/release-android.sh`, ולמזג PR עם `public/android/latest.json`. הסקריפט מעלה את ה-APK ל-release במאגר הציבורי [shaon-android](https://github.com/perlinium-cmd/shaon-android) (Firebase בחינם לא מאפשר קבצי APK). הטלפונים יציגו "יש גרסה חדשה" בפעם הבאה שהאפליקציה תיפתח.

## תהליך עבודה
1. `main` הוא הענף היציב – לא דוחפים אליו ישירות.
2. כל שינוי בענף חדש (`feat/...`, `fix/...`) ← Pull Request ← מיזוג (squash).
