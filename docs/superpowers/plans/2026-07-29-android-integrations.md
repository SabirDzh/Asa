# Android Integrations Plan

> Source: user request, 2026-07-29
> Goal: integrate the Asa task manager with the Android ecosystem and popular services.

## Priority S (Must have)

- [ ] 0. Подготовь архитектуру к добавлению всех интеграций, после этого определи, что надо будет писать на котлин, что на флаттер, для лучшего взаимодействия, только после подготовки архитектуры, приступай к реализации, чтобы не радувать сам флаттер код
- [ ] 1. Calendar API
  - Create events
  - Link tasks to events
  - Update events
  - Delete events
  - Select calendar
  - Support: Google, Samsung, Xiaomi, Oppo, Vivo, Huawei (via Android Calendar Provider)
- [ ] 2. Android Reminders
  - Exact time
  - Repeat
  - Snooze
  - Reschedule
  - Notification after reboot
  - Use AlarmManager + WorkManager
- [ ] 3. Notification API
  - Actions from notification: Done, In an hour, Tomorrow, Edit
  - Notification channels (Work, Home, Personal, Shopping)
  - Priority: Silent, Heads-up, Persistent
- [ ] 4. Quick Settings Tile
  - Quick add task
  - Today shortcut
- [ ] 5. Widgets
  - Small, Medium, Large
  - Today, All tasks, Quick add, Next task, Pinned list
- [ ] 6. Dynamic Color
  - Material You / dynamic_color on Android 12+
- [ ] 7. App Shortcuts
  - Long-press icon: Add, Today, Work, Shopping
- [ ] 8. Share Target
  - Share → Asa → create task
  - Chrome, Telegram, WhatsApp, Discord, Files, YouTube

## Priority A

- [ ] 9. Android Sharesheet
  - Catch text, image, PDF, link, contact, coordinates → create task
- [ ] 10. Clipboard API
  - Offer to create task from copied text
- [ ] 11. Voice Input
  - SpeechRecognizer or Gemini Voice → parse date/time → create task
- [ ] 12. Gemini integration
  - "Break this project into tasks"
  - "Make a checklist"
- [ ] 13. Google Assistant
  - "Add task buy bread"
- [ ] 14. App Search
  - Jetpack AppSearch
- [ ] 15. Global Search
  - Find tasks from phone search

## Priority A+

- [ ] 16. Contacts
  - "Call Ivan" → auto pick contact
- [ ] 17. Phone
  - After call → create task
- [ ] 18. SMS
  - From SMS → create task
- [ ] 19. Email
  - From Gmail → add to Asa
- [ ] 20. Files
  - Attach PDF, Word, Excel, Photo, Video, ZIP
- [ ] 21. Camera
  - Take receipt photo → task
- [ ] 22. Gallery
  - Add photo to task
- [ ] 23. Scanner
  - ML Kit text recognition

## Priority B

- [ ] 24. Maps
  - Task with place, geofencing notification
- [ ] 25. NFC
  - Tap tag → open task
- [ ] 26. Bluetooth
  - Connect to car → show reminder
- [ ] 27. Wi-Fi
  - Home Wi-Fi → home tasks
- [ ] 28. Location
  - At store → shopping
- [ ] 29. QR
  - Scan → create task
- [ ] 30. Barcode
  - Shopping list

## Priority B+

- [ ] 31. Wear OS
  - View, mark done, voice input
- [ ] 32. Android Auto
  - "Remind me to buy gas"
- [ ] 33. Android TV
  - Minimal support
- [ ] 34. Foldables
  - Samsung Fold, Pixel Fold, Honor Magic V
- [ ] 35. Tablets
  - Adaptive UI
- [ ] 36. Desktop Mode
  - Samsung DeX, Android Desktop

## Priority C

- [ ] 37. Nearby Share / Quick Share
  - Share task
- [ ] 38. Drag & Drop
  - Drop file → task
- [ ] 39. Multi-window
  - Full support
- [ ] 40. Picture in Picture
  - Optional

## Cross-cutting requirements

- All integrations via Android Intents where applicable:
  - ACTION_SEND
  - ACTION_SEND_MULTIPLE
  - ACTION_VIEW
  - ACTION_EDIT
  - ACTION_INSERT
  - ACTION_PICK
  - ACTION_CREATE_DOCUMENT
  - ACTION_OPEN_DOCUMENT
  - ACTION_PROCESS_TEXT
  - ACTION_WEB_SEARCH
  - ACTION_ASSIST
