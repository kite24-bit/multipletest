# Output Rules: Generate Automation Test Maestro

> **Untuk AI assistant (Claude):** ikuti aturan ini setiap kali diminta membuat atau mengubah
> automation test di project ini. Latar belakang, alasan, dan detail CI ada di
> `MAESTRO_CI_KNOWLEDGE.md`. Kalau ada aturan yang bertabrakan dengan permintaan user,
> ikuti permintaan user lalu sebutkan aturan mana yang dilanggar.
>
> **Cara pakai:** taruh file ini di root repo, lalu tambahkan `@MAESTRO_TEST_RULES.md` di `CLAUDE.md`.

---

## A. Lingkup

1. Framework E2E **hanya Maestro**. Jangan menambahkan atau mengusulkan framework lain kecuali diminta.
2. Menambah test **cukup menambah file flow**. Workflow menemukan flow baru secara otomatis, jadi **jangan mengubah** `.github/workflows/maestro.yml` atau `.github/scripts/maestro_to_allure.py` kecuali diminta.
3. Jangan membuat shell script (`scripts/*.sh`) untuk menjalankan test.
4. Ubah seminimal mungkin. Jangan merapikan atau mengubah file yang tidak terkait.

## B. File & penamaan

5. **Satu test case = satu file** di `.maestro/flows/`. Edge case juga punya file sendiri, satu skenario per file.
6. Format nama file: `NN_<fitur>_<skenario>.yaml`. Gunakan snake_case, **unik**, dan **tanpa spasi**. Lanjutkan nomor `NN` dari file terakhir, dan kelompokkan nomor per fitur (contoh: `01_login_sukses.yaml`, `02_login_password_salah.yaml`).
7. Langkah yang dipakai berulang (misalnya login) dibuat jadi subflow di `.maestro/subflows/<nama>.yaml`, lalu dipanggil dengan `runFlow`. **Jangan** taruh subflow di `.maestro/flows/`, karena nanti ikut jalan sebagai test sendiri.

## C. Header flow

8. Setiap flow wajib punya header:
   ```yaml
   appId: <applicationId app, termasuk suffix flavor kalau ada>
   name: <kalimat deskriptif yang unik — jadi judul test di Allure>
   tags:
     - smoke        # atau regression
   ---
   ```
9. `name` harus unik di semua flow, karena Allure memakainya untuk mengenali riwayat test.
10. Setiap flow minimal punya satu tag: `smoke` (alur utama yang kritis) atau `regression`.

## D. Isi flow

11. **Flow harus mandiri.** Mulai dengan `launchApp` + `clearState: true`, dan jangan bergantung pada flow lain atau urutan jalan. Flow dibagi ke shard berbeda dan urutannya tidak dijamin.
12. Setelah `launchApp`, tunggu layar pertama dengan `extendedWaitUntil` + `visible: <elemen yang pasti muncul>` + `timeout: 60000`.
13. **Tambahkan `takeScreenshot` setelah setiap step**, dengan nama bernomor yang unik di dalam flow (`01_launch`, `02_halaman_login`, ...).
    - Jangan taruh `takeScreenshot` di dalam `repeat`. Taruh setelah bloknya.
    - Setelah `runFlow`, tambahkan satu `takeScreenshot`.
14. Setiap flow **wajib diakhiri assert** atas hasil akhirnya (`assertVisible` / `assertNotVisible`). Tidak boleh ada flow tanpa assert.
15. Jangan pakai jeda tetap (`waitForAnimationToEnd` sebagai pengganti assert, atau sleep). Pakai `assertVisible` atau `extendedWaitUntil`; Maestro sudah menunggu otomatis.
16. Skenario background/foreground: `pressKey: Home` → `assertNotVisible` → `launchApp` + `stopApp: false`. Di sini jangan pakai `clearState`.
17. Tambahkan komentar Bahasa Indonesia hanya untuk langkah yang tidak jelas maksudnya.

## E. Selector

18. Urutan pilihan selector, dari yang paling stabil:
    1. `id: "<identifier>"` dari `Semantics(identifier: ...)` di Flutter (Flutter ≥ 3.19; belum diuji di proyek percobaan);
    2. teks yang terlihat, misalnya `Text('Masuk')` → `"Masuk"`;
    3. `tooltip` untuk `IconButton` / `FloatingActionButton`;
    4. `Semantics(label: ...)`.
19. Teks selector adalah **regex yang harus cocok penuh**. Escape karakter `+ ( ) . ? * [ ]`, contohnya `"Total \\(2\\)"`.
20. **Jangan** tap berdasarkan koordinat atau index kalau ada pilihan lain. Kalau elemen tidak punya teks atau identifier, **beritahu user** dan usulkan penambahan `Semantics(identifier: ...)` di kode aplikasi. Jangan mengubah kode aplikasi diam-diam.
21. Kalau aplikasi multi-bahasa, utamakan `id`, supaya test tidak bergantung pada teks terjemahan.

## F. Data & rahasia

22. **Jangan** menulis kredensial atau data rahasia di flow. Pakai variabel `${USERNAME}`, `${PASSWORD}`, yang nilainya dikirim lewat `-e` dari GitHub Secrets. Kalau butuh secret baru, sebutkan nama secret dan baris workflow yang perlu ditambah, tapi jangan ubah workflow sendiri tanpa diminta.
23. Data test (nomor akun, nominal, dan sejenisnya) harus aman dijalankan berulang dan paralel. Hindari data yang diubah oleh flow lain di shard berbeda pada waktu yang sama.

## G. Yang dilarang

24. Jangan pakai `executionOrder` di `config.yaml`, karena tidak bisa digabung dengan sharding.
25. Jangan menambahkan filter tag (`--include-tags`, atau `includeTags` di config) di CI tanpa ikut memfilter daftar flow di job `build`. Kalau tidak, flow yang tersaring tercatat sebagai broken.
26. Jangan mengubah trigger workflow, `SHARDS`, versi Maestro, atau konfigurasi emulator kecuali diminta.

## H. Format jawaban saat generate test

27. Mulai dengan **tabel pemetaan**: test case → nama file → tag → ringkasan langkah. Pisahkan alur utama dan edge case.
28. Tulis **isi lengkap setiap file**, tidak boleh potongan atau "dst".
29. Tulis bagian **"Perlu perubahan di aplikasi"** kalau ada elemen yang butuh `Semantics(identifier:)`, beserta usulan kodenya. Kalau tidak ada, tulis "tidak ada".
30. Sertakan perintah untuk menjalankan di lokal:
    ```bash
    maestro test .maestro/flows/<file>.yaml                    # satu flow
    maestro test .maestro/flows/<a>.yaml .maestro/flows/<b>.yaml --config .maestro/config.yaml
    ```
31. Kalau ada emulator atau device, **jalankan flow yang baru dibuat** sebelum menyatakan selesai, dan laporkan hasilnya apa adanya. Kalau tidak bisa dijalankan, katakan bahwa flow belum diuji.
32. Kalau jumlah flow total berubah banyak, sebutkan apakah `SHARDS` sebaiknya disesuaikan. Patokannya: 20–30 flow → 4–5 shard. Cukup sebagai saran, jangan langsung diubah.
33. **Commit lokal saja** (kalau diminta commit). User yang push.
34. Bahasa jawaban: Indonesia santai.

---

## Template flow

```yaml
appId: com.company.app
name: Login berhasil dengan akun valid
tags:
  - smoke
---
- launchApp:
    clearState: true
- takeScreenshot: 01_launch
- extendedWaitUntil:
    visible: "Masuk"
    timeout: 60000
- takeScreenshot: 02_halaman_login
- tapOn:
    id: "login_username"
- inputText: ${USERNAME}
- takeScreenshot: 03_isi_username
- tapOn:
    id: "login_password"
- inputText: ${PASSWORD}
- takeScreenshot: 04_isi_password
- tapOn: "Masuk"
- takeScreenshot: 05_tap_masuk
- assertVisible: "Beranda"
- takeScreenshot: 06_beranda
```

Template subflow (`.maestro/subflows/login.yaml`) dan cara memakainya:

```yaml
appId: com.company.app
---
- tapOn:
    id: "login_username"
- inputText: ${USERNAME}
- tapOn:
    id: "login_password"
- inputText: ${PASSWORD}
- tapOn: "Masuk"
- assertVisible: "Beranda"
```

```yaml
# di dalam flow
- runFlow: ../subflows/login.yaml
- takeScreenshot: 03_setelah_login
```

## Checklist sebelum menyerahkan hasil

- [ ] Satu file per test case, nama `NN_<fitur>_<skenario>.yaml`, unik, tanpa spasi
- [ ] Header lengkap: `appId`, `name` unik, `tags`
- [ ] Mulai dengan `launchApp clearState: true` + `extendedWaitUntil` 60 detik
- [ ] `takeScreenshot` bernomor setelah setiap step, tidak di dalam `repeat`
- [ ] Diakhiri assert hasil akhir
- [ ] Selector stabil, karakter regex di-escape, tanpa koordinat
- [ ] Tanpa kredensial hardcode
- [ ] Workflow dan converter tidak diubah
- [ ] Hasil uji lokal dilaporkan apa adanya
