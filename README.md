# מערכת ניהול שעות עובדות (שאון)

- `public/` – אפליקציית ווב (Firebase Hosting + Firestore)
- `mac/` – אפליקציית macOS (SwiftUI)
- `firestore.rules` – כללי אבטחה

## תהליך עבודה
1. `main` הוא הענף היציב – לא דוחפים אליו ישירות.
2. כל שינוי בענף חדש (`feat/...`, `fix/...`) ← Pull Request ← מיזוג (squash).
