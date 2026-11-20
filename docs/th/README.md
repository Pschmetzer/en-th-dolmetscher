# Dolmetscher EN ⇄ TH (ภาษาไทย)

> **หมายเหตุ:** ข้อความนี้จัดทำด้วยเครื่องแปลและ**ยังไม่ได้รับการตรวจโดยเจ้าของภาษา** อาจมีข้อผิดพลาด หากพบคำที่ไม่ถูกต้อง โปรดแจ้งตามวิธีใน [MUTTERSPRACHLER.md](../MUTTERSPRACHLER.md) (เป็นภาษาเยอรมัน)
>
> **Notice:** This text was machine-translated and has **not been checked by native speakers**. Corrections are welcome, see [MUTTERSPRACHLER.md](../MUTTERSPRACHLER.md) (German).

เอกสารฉบับเต็ม (ภาษาอังกฤษ): [README.md](../../README.md) · ภาษาอังกฤษ: [Quick start](../en/QUICKSTART.md), [FAQ](../en/FAQ.md), [Privacy in brief](../en/PRIVACY-SHORT.md)

## แอปนี้คืออะไร

Dolmetscher คือล่ามแบบไม่ต้องใช้มือ: คุณแค่พูด ระบบจะแปลเป็นภาษาของคู่สนทนาแล้วอ่านออกเสียงทันที และคำตอบของเขาจะกลับมาเป็นภาษาของคุณ บน Mac และ iPhone แอปจะ**ตรวจจับเองว่ากำลังพูดภาษาใด** จึงไม่ต้องกดปุ่มสลับภาษา ค่าเริ่มต้นคืออังกฤษ ⇄ ไทย แต่เลือกคู่ภาษาใดก็ได้จากทั้งหมด 19 ภาษา

| แพลตฟอร์ม | คืออะไร |
|---|---|
| **Mac** (Apple Silicon, macOS 14 ขึ้นไป) | แอปเต็มรูปแบบ มีเมนูบาร์ คำสั่งเสียง โปรไฟล์เสียง และการแปลด้วย Claude |
| **iPhone / iPad** (iOS 26 ขึ้นไป) | แอปคู่หูแบบเนทีฟ มีวิดเจ็ต สร้างเองด้วย Xcode |
| **เบราว์เซอร์** (Chrome) | [Web Lite](https://pschmetzer.github.io/en-th-dolmetscher/) ไฟล์ HTML ไฟล์เดียว ติดตั้งเป็นแอปได้ (PWA) |

## ดาวน์โหลดและติดตั้ง

ตอนนี้**ยังไม่มีไฟล์ดาวน์โหลดสำเร็จรูป** ต้องสร้างแอปจากซอร์สโค้ดเอง ขั้นตอนอย่างย่ออยู่ใน [QUICKSTART.md](QUICKSTART.md)

- **Mac:** ต้องใช้ Mac ที่มี Apple Silicon (M1 ขึ้นไป ไม่รองรับ Intel) และ macOS 14 ขึ้นไป รันคำสั่ง `./build.sh --install` แล้วแอปจะติดตั้งที่ `~/Applications/Dolmetscher.app`
- **iPhone / iPad:** ต้องใช้ Xcode 26 ขึ้นไปบน Mac และ iOS 26 ขึ้นไป เปิด `ios/Dolmetscher.xcodeproj` Apple ID ฟรีก็เพียงพอ แต่แอปที่สร้างเองด้วยบัญชีฟรีจะหมดอายุใน 7 วันและต้องติดตั้งใหม่จาก Xcode รายละเอียด: [ios/README.md](../../ios/README.md)
- **เว็บ:** ไม่ต้องติดตั้ง เปิด <https://pschmetzer.github.io/en-th-dolmetscher/> ใน **Chrome**

## ฟังก์ชันหลัก

- ตรวจจับภาษาที่พูดโดยอัตโนมัติ (Mac และ iPhone) ในเบราว์เซอร์ต้องเลือกฝั่งเอง
- 19 ภาษา เลือกคู่ภาษาใดก็ได้
- สมุดวลีพร้อมชุดสถานการณ์ 111 ชุด (เช่น หมอ ร้านขายยา ตำรวจ ร้านอาหาร แท็กซี่ วัด) มีหมายเหตุทางวัฒนธรรม และประโยคสำคัญ เช่น เรื่องการแพ้ จะขึ้นก่อน
- มุมมองสำหรับคู่สนทนาที่ตัวอักษรขนาดใหญ่ (Mac, iPhone, เบราว์เซอร์)
- คำสั่งเสียง ขึ้นต้นด้วย "Translator, ..." (พูดเป็นภาษาอังกฤษ ใช้ได้เมื่อภาษาอังกฤษเป็นหนึ่งในสองภาษา) ดู [VOICE-COMMANDS.md](../en/VOICE-COMMANDS.md)
- แปลบนอุปกรณ์โดยไม่ต้องใช้อินเทอร์เน็ต (iPhone เป็นค่าเริ่มต้น เมื่อติดตั้งชุดภาษาออฟไลน์แล้ว)
- โหมดสนทนา การ์ดคำตอบ โหมดเรียนรู้ และหน้าจอฉุกเฉิน (iPhone) ตารางเปรียบเทียบครบอยู่ใน [README.md](../../README.md)

## ความเป็นส่วนตัว

ไม่มีบัญชี ไม่มีการเก็บสถิติ และไม่มีเซิร์ฟเวอร์ของเราเอง สรุปสั้นๆ: [PRIVACY-SHORT.md](PRIVACY-SHORT.md)

## เอกสารอื่น

[QUICKSTART.md](QUICKSTART.md) · [FAQ.md](FAQ.md) · [PRIVACY-SHORT.md](PRIVACY-SHORT.md) · แก้ปัญหา (ภาษาอังกฤษ): [TROUBLESHOOTING.md](../en/TROUBLESHOOTING.md)
