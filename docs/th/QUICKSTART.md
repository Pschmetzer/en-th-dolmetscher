# เริ่มต้นใช้งานอย่างเร็ว

> **หมายเหตุ:** ข้อความนี้จัดทำด้วยเครื่องแปลและ**ยังไม่ได้รับการตรวจโดยเจ้าของภาษา** อาจมีข้อผิดพลาด หากพบคำที่ไม่ถูกต้อง โปรดแจ้งตามวิธีใน [MUTTERSPRACHLER.md](../MUTTERSPRACHLER.md) (เป็นภาษาเยอรมัน)
>
> **Notice:** This text was machine-translated and has **not been checked by native speakers**. Corrections are welcome, see [MUTTERSPRACHLER.md](../MUTTERSPRACHLER.md) (German).

English: [QUICKSTART.md](../en/QUICKSTART.md) · ภาพรวม: [README.md](README.md) · เมื่อมีปัญหา (ภาษาอังกฤษ): [TROUBLESHOOTING.md](../en/TROUBLESHOOTING.md)

มี 3 วิธี ขึ้นอยู่กับอุปกรณ์ของคุณ

## Mac (Apple Silicon, macOS 14 ขึ้นไป)

ยังไม่มีไฟล์ดาวน์โหลดสำเร็จรูป ต้องสร้างแอปจากซอร์สโค้ด

1. สิ่งที่ต้องมี: Mac ที่มี Apple Silicon (M1 ขึ้นไป ไม่ใช่ Intel), Xcode Command Line Tools (`xcode-select --install`) และ [uv](https://docs.astral.sh/uv/) (`brew install uv`) ไม่ต้องใช้ Python ของ Homebrew และ ffmpeg
2. ดาวน์โหลดโค้ด: `git clone https://github.com/Pschmetzer/en-th-dolmetscher.git` แล้วเปิดโฟลเดอร์ใน Terminal
3. สร้างและติดตั้ง: `./build.sh --install` คำสั่งนี้ติดตั้ง `~/Applications/Dolmetscher.app` และบน Mac ที่ใช้สร้างจะดาวน์โหลดโมเดลเสียง (`medium`, `small` และโมเดลภาษาไทย รวมประมาณ 3.5 GB ครั้งเดียว)
4. เปิดแอป กด **Start** (หรือกดแป้นเว้นวรรค) และอนุญาตการเข้าถึงไมโครโฟน
5. พูดได้เลย แอปตรวจจับว่าพูดภาษาใดในสองภาษา (ค่าเริ่มต้น: อังกฤษและไทย) แปลและอ่านออกเสียง คู่ภาษา ไมโครโฟน และเสียง ตั้งค่าได้ในการตั้งค่า

**เปิดครั้งแรกบน Mac เครื่องอื่น:** หากคัดลอกแอปไปยัง Mac ที่ไม่มีสภาพแวดล้อม Python จะมีหน้าจอตั้งค่าขึ้นมา แสดงขนาดดาวน์โหลดและพื้นที่ว่างในดิสก์ ดาวน์โหลด Python 3.12 ของตัวเอง แพ็กเกจ และโมเดล (พร้อมแถบความคืบหน้า) ยกเลิกและลองใหม่ได้ ต้องใช้อินเทอร์เน็ต

แป้นพิมพ์ลัด: [SHORTCUTS.md](../en/SHORTCUTS.md) · คำสั่งเสียง ("Translator, ..."): [VOICE-COMMANDS.md](../en/VOICE-COMMANDS.md)

## iPhone / iPad (iOS 26 ขึ้นไป)

ไม่มีใน App Store ต้องสร้างแอปเอง Apple ID ฟรีก็เพียงพอ รายละเอียด: [ios/README.md](../../ios/README.md)

1. Xcode 26 ขึ้นไปบน Mac แล้วรัน `open ios/Dolmetscher.xcodeproj`
2. Xcode, Settings, Accounts: เพิ่ม Apple ID ของคุณ
3. Target **Dolmetscher**, Signing & Capabilities: เลือกทีมของคุณ และเปลี่ยน bundle identifier (`com.pschmetzer.dolmetscher`) เป็นค่าที่ไม่ซ้ำ
4. เชื่อมต่อ iPhone เลือกเป็นปลายทาง แล้วกด Run (⌘R) ครั้งแรกบน iPhone: Settings, General, VPN & Device Management เพื่อเชื่อถือใบรับรองผู้พัฒนา และเปิด Developer Mode หาก iOS ถาม
5. อนุญาตไมโครโฟนและการรู้จำเสียงพูด กด Start แล้วพูด

เมื่อติดตั้งชุดภาษาออฟไลน์ของคู่ภาษาแล้ว การแปลจะทำงานบนอุปกรณ์ หากขาดชุดภาษาใด ข้อความจะออกอินเทอร์เน็ตก็ต่อเมื่อเปิด "Online translator as fallback" (ค่าเริ่มต้น: ปิด) แอปที่สร้างเองด้วยบัญชีฟรีจะหมดอายุใน 7 วันและต้องติดตั้งใหม่จาก Xcode

## เบราว์เซอร์ (Web Lite)

ไม่ต้องติดตั้ง เปิด <https://pschmetzer.github.io/en-th-dolmetscher/> ใน **Chrome** (Firefox ไม่มีการรู้จำเสียงพูด Safari ใช้ได้เฉพาะเมื่อเปิดการป้อนด้วยเสียง และมีข้อจำกัด)

1. ยอมรับครั้งเดียวก่อนเริ่มไมโครโฟนครั้งแรก และอนุญาตไมโครโฟนในเบราว์เซอร์
2. เลือกภาษา (ค่าเริ่มต้น: อังกฤษและไทย)
3. เลือกเองว่าใครพูด: **E** (หรือ 1) สำหรับภาษาของคุณ **T** (หรือ 2) สำหรับภาษาของอีกฝ่าย **Space** เพื่อจบ หน้าเว็บไม่ตรวจจับภาษาอัตโนมัติ
4. ทางเลือก: "Add to home screen" (PWA) หน้าเว็บและสมุดวลีจะเปิดแบบออฟไลน์ได้ แต่การแปลต้องใช้เครือข่าย
