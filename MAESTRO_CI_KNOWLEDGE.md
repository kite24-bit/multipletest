# Knowledge Transfer: Maestro E2E + GitHub Actions + Allure (Flutter Android)

> **Untuk AI assistant (Claude) yang membaca file ini:** ini adalah ringkasan keputusan,
> preferensi, template, dan pelajaran dari proyek percobaan (`testflutter`) yang sudah
> **terbukti jalan** di GitHub Actions. Gunakan ini sebagai acuan saat membuat test Maestro,
> workflow CI, dan reporting di proyek nyata. Ikuti bagian **Preferensi kerja** di bawah;
> user tidak mau mengajari ulang hal yang sama.
>
> **Cara pakai di proyek nyata:** salin file ini ke root repo, lalu di `CLAUDE.md` tambahkan
> baris `@MAESTRO_CI_KNOWLEDGE.md` agar otomatis terbaca setiap sesi.
>
> **Aturan ringkas untuk generate test** ada di `MAESTRO_TEST_RULES.md`; bawa kedua file ini ke project nyata.

---

## 1. Preferensi kerja user (WAJIB diikuti)

| Topik | Aturan |
|---|---|
| Bahasa | Bahasa Indonesia santai. Komentar di file YAML/script juga Bahasa Indonesia. |
| Ruang lingkup perubahan | **Ubah seminimal mungkin.** Jangan merombak banyak file sekaligus. User pernah protes karena terlalu banyak yang diganti. |
| Pilih yang bawaan dulu | Pakai fitur/format bawaan tool dulu (contoh: format report bawaan) sebelum membuat solusi custom. Custom hanya kalau bawaan memang tidak cukup, dan jelaskan alasannya. |
| CI | **GitHub Actions murni**, tanpa shell script terpisah (`scripts/*.sh` sulit di-maintain). Logic ditulis langsung di workflow. Pengecualian yang sudah disetujui: converter Python `maestro_to_allure.py` (Maestro tidak punya output Allure). |
| Git | **Commit lokal saja.** User push sendiri. Jangan push, buat PR, atau trigger workflow tanpa diminta. |
| Trigger workflow | Maestro jalan kalau **ada push ke `uat` DAN workflow `pr-ai-code-review.yml` (name: `PR AI Code Review`) untuk push itu lolos tanpa error**, plus `workflow_dispatch` manual. Caranya `workflow_run` + cek `conclusion == 'success'` (lihat bagian 5). |
| Reporting | Satu laporan Allure untuk Maestro. Hasil semua flow/shard digabung jadi **satu** laporan (mirip test suite), walaupun test case-nya tetap terpisah per file dan job. |
| Screenshot | Setiap step di laporan Allure harus punya screenshot. |
| Framework | **Hanya Maestro.** Jangan tambahkan atau usulkan framework E2E lain kecuali diminta. |
| Validasi | Jalankan `actionlint` untuk setiap perubahan workflow sebelum commit. |

---

## 2. Stack & keputusan

| Komponen | Pilihan | Alasan |
|---|---|---|
| E2E framework | **Maestro**, versi dipin lewat env `MAESTRO_VERSION` (saat ini 2.12.1) | Flow berupa YAML sederhana, satu file per test case, black-box (APK biasa tanpa instrumentasi), dan mudah diparalelkan. |
| Emulator di CI | `reactivecircus/android-emulator-runner@v2`, `api-level: 34`, `target: google_apis`, `arch: x86_64` | Emulator berjalan headless otomatis. `google_apis` (tanpa Play Store) menghindari dialog "Google Play Store keeps stopping". |
| Paralel di CI | **Matrix per shard** (`SHARDS` di `env`, default 2). Flow dibagi round-robin ke shard; tiap shard = 1 job + 1 emulator, flow di dalamnya jalan berurutan (`maestro test a.yaml b.yaml`). | Boot emulator + install Maestro (±2–3 menit) cuma sekali per shard, bukan per flow. `--shard-split` bawaan Maestro butuh banyak device di **satu mesin**, sedangkan runner GitHub (emulator-runner) cuma 1 emulator per job, jadi sharding dilakukan lewat matrix. Daftar flow dibuat otomatis dengan `find`. |
| Paralel di lokal | `maestro --device a,b test .maestro --shard-split 2` | Satu perintah untuk banyak emulator di satu mesin. |
| Build | APK **release** dibangun **sekali** di job `build`, lalu dibagikan lewat artifact ke semua job test. | Menghemat waktu; setiap job test tidak perlu Flutter. Release jauh lebih kecil (~42 MB vs ~157 MB debug) dan lebih cepat di emulator (3 flow: ~27 detik vs ~1 menit), dan Maestro black-box sehingga tidak butuh build debug. |
| Reporting | **Allure 2.46.2** (`allure generate --single-file`), sumbernya hasil konversi `commands.json` Maestro | JUnit Maestro tidak berisi step, dan report HTML Maestro hanya per job (tidak bisa digabung). Allure bisa menggabungkan semua flow + step + screenshot. |
| Artifact untuk debug | `maestro-debug-<flow>` (folder `--test-output-dir` mentah) | Untuk investigasi ketika flow gagal. |

---

## 3. Struktur folder

```
.maestro/
  config.yaml                 # workspace config: flows: ["flows/*"]
  flows/
    01_<nama_test>.yaml       # SATU test case per file
    02_<nama_test>.yaml
.github/
  workflows/maestro.yml       # build -> matrix per shard -> allure-report
  scripts/maestro_to_allure.py  # converter commands.json -> Allure results
```

`.maestro/config.yaml`:

```yaml
# Konfigurasi workspace Maestro.
# `maestro test .maestro` menjalankan semua flow di bawah ini.
# Saat sharding, urutan flow tidak dijamin, jadi tiap flow harus mandiri
# (masing-masing mulai dengan `launchApp: clearState: true`).
flows:
  - "flows/*"
```

---

## 4. Konvensi menulis flow Maestro

### Aturan

1. **Satu file = satu test case.** Nama file diberi nomor urut dan snake_case, misalnya `02_tambah_counter.yaml`. Nama file (tanpa `.yaml`) menjadi `subSuite` di Allure.
2. Header berisi `appId`, `name` (kalimat deskriptif, tampil sebagai judul test di Allure), dan `tags` (`smoke` / `regression` / dst). Header ditutup dengan `---`.
3. **Setiap flow harus mandiri**: mulai dengan `launchApp: clearState: true`. Urutan dan device tidak dijamin.
4. Setelah launch, gunakan `extendedWaitUntil` sampai elemen halaman utama terlihat, dengan `timeout: 60000`. Launch pertama di emulator yang baru boot bisa lambat.
5. **Pasang `takeScreenshot` setelah setiap step**, dengan nama bernomor yang unik di dalam flow (`01_launch`, `02_halaman_utama`, ...). Converter menempelkan gambar ke step **sebelumnya** di level yang sama, dan step `takeScreenshot` sendiri disembunyikan.
   - Jangan taruh `takeScreenshot` di dalam `repeat`. Taruh setelah blok `repeat`; gambarnya akan menempel ke step "Repeat N times".
   - Nama harus unik di dalam flow, karena file dengan nama sama akan tertimpa.
6. Selector teks di Maestro adalah **regex yang harus cocok penuh**. Escape karakter khusus seperti `+ ( ) . ? *`, contohnya `"Total \\(2\\)"`.
7. Selector untuk Flutter (Maestro membaca accessibility tree):
   - `Text('Halo')` → `"Halo"`.
   - `FloatingActionButton` / `IconButton` dengan `tooltip: 'Increment'` → `"Increment"`.
   - Widget tanpa teks: tambahkan `Semantics(label: '...')`, atau `Semantics(identifier: 'login_button')` lalu pakai `id: "login_button"` di Maestro (identifier memerlukan Flutter ≥ 3.19; belum diuji di proyek percobaan).
8. Untuk skenario background/foreground: `pressKey: Home` → assert app tidak terlihat → `launchApp: stopApp: false`. Jangan pakai `clearState` di sini supaya state tetap ada.

### Template flow

```yaml
appId: com.example.testflutter
name: Tombol + menambah counter
tags:
  - regression
---
# Tiap `takeScreenshot` dilampirkan ke step sebelumnya di laporan Allure
# (lihat .github/scripts/maestro_to_allure.py).
- launchApp:
    clearState: true
- takeScreenshot: 01_launch
# Launch pertama setelah emulator boot bisa lambat.
- extendedWaitUntil:
    visible: "Flutter Demo Home Page"
    timeout: 60000
- takeScreenshot: 02_halaman_utama
- assertVisible: "0"
- takeScreenshot: 03_counter_0
- tapOn: "Increment"
- takeScreenshot: 04_tap_increment
- assertVisible: "1"
- takeScreenshot: 05_counter_1
- repeat:
    times: 4
    commands:
      - tapOn: "Increment"
- takeScreenshot: 06_setelah_tap_4x
- assertVisible: "5"
- takeScreenshot: 07_counter_5
```

Contoh background:

```yaml
- pressKey: Home
- takeScreenshot: 06_home
- assertNotVisible: "Flutter Demo Home Page"
- takeScreenshot: 07_app_di_background
- launchApp:
    stopApp: false
- takeScreenshot: 08_app_dibuka_lagi
- assertVisible: "2"
- takeScreenshot: 09_counter_tetap_2
```

---

## 5. Workflow GitHub Actions (`.github/workflows/maestro.yml`)

Alurnya ada 3 tahap:

0. **Syarat trigger**: workflow tidak dipicu langsung oleh push. Ia menunggu `PR AI Code Review` selesai (`workflow_run`, `branches: [uat]`), lalu job `build` hanya jalan kalau review dipicu oleh `push` dan `conclusion == 'success'`. Kalau `build` di-skip, semua job lain ikut skip.
1. **`build`**: membangun APK **release** sekali, meng-upload-nya sebagai artifact, lalu membagi flow ke `SHARDS` shard (JSON untuk matrix).
2. **`maestro`** (matrix): satu job per shard, semuanya paralel. Setiap job menyalakan emulator headless, install APK, menjalankan semua flow shard itu dengan satu `maestro test`, mengonversi hasil ke Allure, lalu meng-upload `maestro-allure-<shard>` dan `maestro-debug-<shard>`.
3. **`allure-report`**: mengunduh semua `maestro-allure-*` ke **satu folder** (`merge-multiple: true`, aman karena nama file berupa UUID). Hasilnya **satu** `index.html`, ringkasan pass/fail di Job Summary, dan artifact `allure-report-maestro`.

Versi ini **sudah terbukti hijau** di CI:

```yaml
name: Maestro E2E
run-name: Maestro E2E (${{ github.event.workflow_run.head_branch || github.ref_name }})

# Syarat jalan: ada push ke branch uat DAN workflow "PR AI Code Review" untuk
# push itu selesai tanpa error. Jadi workflow ini menunggu review selesai
# (workflow_run), lalu job `build` mengecek hasilnya.
# Catatan: trigger workflow_run hanya aktif kalau file ini sudah ada di
# default branch (main).
on:
  workflow_run:
    # Harus sama persis dengan `name:` di pr-ai-code-review.yml.
    workflows: [PR AI Code Review]
    types: [completed]
    branches: [main]
  workflow_dispatch:

# workflow_run berjalan dengan hak akses penuh repo; batasi token ke
# read-only karena workflow ini menjalankan kode dari branch yang direview.
permissions:
  contents: read

env:
  ALLURE_VERSION: 2.46.2
  # Jumlah shard = jumlah emulator/job paralel. Flow dibagi rata ke tiap
  # shard, lalu dijalankan berurutan di emulator shard tersebut. Overhead
  # boot emulator + install Maestro cuma sekali per shard, bukan per flow.
  SHARDS: 2
  MAESTRO_CLI_NO_ANALYTICS: 1
  # Versi Maestro dipin (dibaca installer) sekaligus jadi key cache.
  MAESTRO_VERSION: 2.12.1
  # Konfigurasi emulator; juga jadi key cache snapshot AVD.
  EMULATOR_API: 34
  # google_apis = tanpa Play Store, jadi tidak ada dialog
  # "Google Play Store keeps stopping" yang bikin flow gagal palsu.
  EMULATOR_TARGET: google_apis
  EMULATOR_ARCH: x86_64
  EMULATOR_OPTIONS: -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none

jobs:
  # 1. Build APK sekali, dipakai ulang oleh semua job test.
  #    Sekalian membagi flow ke shard untuk matrix, jadi flow baru di
  #    .maestro/flows/ otomatis ikut jalan tanpa mengubah workflow ini.
  build:
    # Syarat: review dipicu oleh push (bukan PR) dan lolos tanpa error.
    # Dijalankan manual (workflow_dispatch) selalu boleh.
    if: >-
      github.event_name == 'workflow_dispatch' ||
      (github.event.workflow_run.event == 'push' &&
       github.event.workflow_run.conclusion == 'success')
    runs-on: ubuntu-latest
    outputs:
      shards: ${{ steps.shards.outputs.list }}
    steps:
      # workflow_run defaultnya checkout main; ambil commit yang direview.
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.workflow_run.head_sha || github.sha }}

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.38.10
          channel: stable
          cache: true

      # Release: lebih kecil (~42 MB vs ~157 MB debug) dan jauh lebih cepat
      # di emulator. Maestro black-box, jadi tidak butuh build debug.
      # APK release tetap berisi x86_64, jadi bisa jalan di emulator CI.
      - run: flutter build apk --release

      - uses: actions/upload-artifact@v4
        with:
          name: app-release-apk
          path: build/app/outputs/flutter-apk/app-release.apk

      # Bagi flow ke shard secara round-robin, contoh SHARDS=2 dengan 3 flow:
      # [{"name":"shard-1","flows":"01.yaml 03.yaml"},{"name":"shard-2","flows":"02.yaml"}]
      - id: shards
        run: |
          list=$(find .maestro/flows -name '*.yaml' | sort | jq -R -s -c --argjson n "$SHARDS" 'split("\n") | map(select(length > 0)) as $f | [range([$n, ($f | length)] | min) as $i | {name: "shard-\($i + 1)", flows: ([$f | to_entries[] | select(.key % $n == $i) | .value] | join(" "))}]')
          echo "list=$list" >> "$GITHUB_OUTPUT"

  # 2. Satu job per shard, semuanya jalan paralel, masing-masing dengan
  #    emulator headless sendiri. Flow di dalam shard jalan berurutan.
  maestro:
    needs: build
    runs-on: ubuntu-latest
    timeout-minutes: 45
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.shards) }}
    name: maestro (${{ matrix.shard.name }})
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.workflow_run.head_sha || github.sha }}

      - uses: actions/download-artifact@v4
        with:
          name: app-release-apk

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      # Cache instalasi Maestro: download hanya kalau versi ini belum ada di
      # cache. Pakai restore/save terpisah (bukan actions/cache) supaya cache
      # tetap tersimpan walaupun ada flow yang gagal.
      - name: Restore Maestro cache
        id: maestro-cache
        uses: actions/cache/restore@v4
        with:
          path: ~/.maestro
          key: maestro-${{ env.MAESTRO_VERSION }}

      # Download installer kadang putus (connection reset) tapi installer
      # tidak gagal, jadi coba ulang sampai `maestro --version` berhasil.
      - name: Install Maestro
        if: steps.maestro-cache.outputs.cache-hit != 'true'
        run: |
          for i in 1 2 3; do
            curl -fsSL "https://get.maestro.mobile.dev" | bash && "$HOME/.maestro/bin/maestro" --version && break
            echo "Install Maestro gagal (percobaan $i), coba lagi..."
            sleep 10
          done
          "$HOME/.maestro/bin/maestro" --version

      - name: Save Maestro cache
        if: steps.maestro-cache.outputs.cache-hit != 'true'
        uses: actions/cache/save@v4
        with:
          path: ~/.maestro
          key: maestro-${{ env.MAESTRO_VERSION }}

      - name: Add Maestro to PATH
        run: |
          "$HOME/.maestro/bin/maestro" --version
          echo "$HOME/.maestro/bin" >> "$GITHUB_PATH"

      # Wajib agar emulator x86_64 bisa pakai akselerasi hardware di runner Linux.
      - name: Enable KVM
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      # Cache snapshot emulator (pola dari README android-emulator-runner):
      # dengan snapshot, emulator langsung resume tanpa cold boot.
      - name: Restore AVD cache
        id: avd-cache
        uses: actions/cache/restore@v4
        with:
          path: |
            ~/.android/avd/*
            ~/.android/adb*
          key: avd-${{ env.EMULATOR_API }}-${{ env.EMULATOR_TARGET }}-${{ env.EMULATOR_ARCH }}

      # Hanya saat cache kosong (run pertama / konfigurasi emulator berubah):
      # boot sekali lalu simpan snapshot-nya.
      - name: Create AVD snapshot
        if: steps.avd-cache.outputs.cache-hit != 'true'
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: ${{ env.EMULATOR_API }}
          target: ${{ env.EMULATOR_TARGET }}
          arch: ${{ env.EMULATOR_ARCH }}
          force-avd-creation: false
          emulator-options: ${{ env.EMULATOR_OPTIONS }}
          disable-animations: false
          script: echo "Snapshot AVD dibuat untuk cache."

      - name: Save AVD cache
        if: steps.avd-cache.outputs.cache-hit != 'true'
        uses: actions/cache/save@v4
        with:
          path: |
            ~/.android/avd/*
            ~/.android/adb*
          key: avd-${{ env.EMULATOR_API }}-${{ env.EMULATOR_TARGET }}-${{ env.EMULATOR_ARCH }}

      # Menyalakan emulator headless dari snapshot, menunggu boot selesai,
      # mematikan animasi, menjalankan `script`, lalu mematikan emulator.
      # -no-snapshot-save: snapshot di cache tetap bersih untuk run berikutnya.
      - name: Run Maestro flow
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: ${{ env.EMULATOR_API }}
          target: ${{ env.EMULATOR_TARGET }}
          arch: ${{ env.EMULATOR_ARCH }}
          force-avd-creation: false
          emulator-options: -no-snapshot-save ${{ env.EMULATOR_OPTIONS }}
          disable-animations: true
          # Tiap baris dijalankan terpisah, jadi tulis satu perintah per baris.
          # --config wajib: Maestro hanya mencari config.yaml otomatis kalau
          # yang dikirim folder, bukan daftar file flow.
          script: |
            adb shell settings put global hide_error_dialogs 1
            adb install -r app-release.apk
            maestro test ${{ matrix.shard.flows }} --config .maestro/config.yaml --test-output-dir maestro-debug

      # Maestro tidak punya output Allure dan JUnit-nya tanpa step, jadi
      # commands.json (detail per langkah + screenshot) dikonversi ke hasil Allure.
      # Daftar flow ikut dikirim: flow yang tidak punya output (mis. Maestro
      # gagal diinstal) tetap masuk laporan sebagai "broken".
      - name: Convert to Allure results
        if: always()
        run: python3 .github/scripts/maestro_to_allure.py maestro-debug allure-results ${{ matrix.shard.flows }}

      # Hasil Allure per shard: bahan laporan gabungan di job `allure-report`.
      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: maestro-allure-${{ matrix.shard.name }}
          path: allure-results/
          if-no-files-found: ignore

      # Screenshot + log per langkah untuk investigasi kalau flow gagal.
      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: maestro-debug-${{ matrix.shard.name }}
          path: maestro-debug/
          if-no-files-found: ignore

  # 3. Gabungkan hasil SEMUA flow jadi SATU laporan Allure.
  allure-report:
    needs: maestro
    # Lewati juga kalau test tidak jalan (review gagal -> build di-skip).
    if: ${{ !cancelled() && needs.maestro.result != 'skipped' }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          pattern: maestro-allure-*
          path: allure-results
          # Nama file hasil Allure unik (UUID), jadi aman digabung ke satu folder.
          merge-multiple: true

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      - name: Install Allure
        run: |
          curl -fsSL -o "$RUNNER_TEMP/allure.zip" "https://repo.maven.apache.org/maven2/io/qameta/allure/allure-commandline/$ALLURE_VERSION/allure-commandline-$ALLURE_VERSION.zip"
          unzip -q "$RUNNER_TEMP/allure.zip" -d "$RUNNER_TEMP/allure"
          dirname "$(find "$RUNNER_TEMP/allure" -path '*/bin/allure' | head -1)" >> "$GITHUB_PATH"

      # Semua hasil flow ada di allure-results/; Allure menggabungkannya jadi
      # satu index.html mandiri (--single-file).
      - name: Generate Allure report
        run: |
          allure generate --single-file --clean -o allure-report allure-results
          jq -r '"### Maestro: \(.stats.passed)/\(.stats.total) passed, \(.stats.failed) failed, \(.stats.broken) broken\n\nDownload artifact **allure-report-maestro** lalu buka `index.html`."' allure-report/summary.json >> "$GITHUB_STEP_SUMMARY"

      - uses: actions/upload-artifact@v4
        with:
          name: allure-report-maestro
          path: allure-report/
```

### Catatan penting workflow

- **Build release di project nyata:** butuh keystore release. Simpan keystore (base64) dan password-nya di GitHub Secrets, lalu tulis `key.properties` sebelum build. Di repo dummy, build release masih ditandatangani debug key bawaan template Flutter, jadi tidak perlu secret.
- **Cek fitur keamanan di build release** sebelum dipakai untuk E2E: deteksi emulator/root (misalnya freeRASP), SSL pinning, atau screenshot blocking (`FLAG_SECURE`) bisa membuat app menutup diri di emulator, request gagal, atau screenshot hitam. Kalau ada, pakai flavor/build khusus test (misalnya `uat`) yang mematikan proteksi itu, atau tanya tim app.
- APK release Flutter default berisi `arm64-v8a`, `armeabi-v7a`, dan `x86_64`, jadi bisa jalan di emulator x86_64 CI. Jangan pakai `--split-per-abi` tanpa memilih APK x86_64.
- **Cache** (hemat waktu per shard): `~/.maestro` di-cache dengan key `maestro-<MAESTRO_VERSION>` (versi dipin lewat env `MAESTRO_VERSION`, yang dibaca installer resmi). Snapshot emulator (`~/.android/avd/*`, `~/.android/adb*`) di-cache dengan key `avd-<api>-<target>-<arch>`, mengikuti pola README `android-emulator-runner`: kalau cache kosong, step `Create AVD snapshot` boot sekali tanpa `-no-snapshot` lalu disimpan; step test memakai `force-avd-creation: false` + `-no-snapshot-save` supaya snapshot di cache tetap bersih.
- Pakai `actions/cache/restore` + `actions/cache/save` terpisah, **bukan** `actions/cache`. `actions/cache` hanya menyimpan cache kalau job sukses, jadi kalau ada flow gagal di run pertama, cache tidak pernah tersimpan.
- Run pertama (atau setelah `MAESTRO_VERSION`/konfigurasi emulator diubah) lebih lama karena membuat cache. Kalau beberapa shard menyimpan key yang sama bersamaan, yang kalah hanya dapat warning "Unable to reserve cache" (tidak gagal).
- Upgrade Maestro = ubah `MAESTRO_VERSION` (pastikan release `cli-<versi>` ada di GitHub mobile-dev-inc/maestro).
- **Cara kerja sharding Maestro** (dicek dari source `TestCommand.kt`): `--shard-split N` membagi flow round-robin (`index % N`) ke N device yang terhubung ke **satu proses Maestro**; kalau device kurang, Maestro error "Not enough devices connected". `--shard-all N` menjalankan **semua** flow di setiap device (bukan untuk mempercepat). Karena satu job GitHub cuma punya satu emulator, pembagian round-robin yang sama dilakukan di job `build` (jq) dan tiap shard jadi satu job matrix.
- Kalau `maestro test` diberi **daftar file** (bukan folder), `config.yaml` **tidak** dicari otomatis. Karena itu workflow memakai `--config .maestro/config.yaml`. Pola `flows:` di config hanya berlaku untuk folder, jadi file yang dikirim eksplisit tetap jalan.
- Filter tag (`--include-tags`/`--exclude-tags`, atau `includeTags`/`excludeTags` di config) membuat flow yang tersaring tidak menghasilkan output, sehingga converter mencatatnya sebagai **broken**. Kalau butuh filter tag di CI, filter juga daftar flow di job `build`.
- `executionOrder` (flow berurutan) di config **tidak bisa** digabung dengan sharding.
- Nama file flow jangan mengandung spasi, karena daftar flow per shard dipisah dengan spasi.
- **`workflow_run` hanya aktif kalau `maestro.yml` sudah ada di default branch (`main`).** Push ke branch lain tidak memicunya sebelum file ini di-merge ke `main`.
- `workflows: [PR AI Code Review]` harus **sama persis** dengan `name:` workflow review di project, bukan nama filenya.
- Workflow review di project **wajib punya trigger `push: branches: [uat]`**. Kalau review hanya jalan di `pull_request`, Maestro tidak akan pernah jalan.
- `workflow_run` men-checkout `main` secara default, jadi setiap `actions/checkout` memakai `ref: ${{ github.event.workflow_run.head_sha || github.sha }}`.
- `permissions: contents: read` membatasi token, karena `workflow_run` berjalan dengan hak akses penuh repo.
- Run hasil `workflow_run` tidak muncul sebagai check di halaman PR; lihat di tab Actions. `run-name` menampilkan nama branch-nya.
- `allure-report` memakai `needs.maestro.result != 'skipped'` agar tidak jalan saat review gagal.
- `script:` di `android-emulator-runner` **menjalankan setiap baris secara terpisah**. Tulis satu perintah per baris. `if`/`for` multi-baris dan variabel antar baris tidak akan jalan.
- Langkah konversi dan upload memakai `if: always()` agar report tetap dibuat ketika flow gagal. Job `allure-report` memakai `if: ${{ !cancelled() && needs.maestro.result != 'skipped' }}`.
- `fail-fast: false` diperlukan agar satu flow yang gagal tidak membatalkan flow lain.
- Allure **hanya membaca file di level teratas** setiap folder hasil, bukan subfolder. Pastikan file `*-result.json` dan attachment berada langsung di folder tersebut. `merge-multiple: true` aman dipakai karena nama filenya UUID.
- Converter dipanggil dengan daftar flow shard. Flow tanpa output tetap masuk laporan sebagai **broken** dengan link ke log run, jadi laporan tidak pernah "hijau palsu".
- Allure tidak punya setup action resmi. Install dari zip Maven Central (butuh Java), lalu cari folder `bin` secara dinamis.
- Job Summary menampilkan baris ringkasan seperti `Maestro: 3/3 passed, ...`. Report lengkap ada di artifact `allure-report-maestro`; unduh lalu buka `index.html`. Report bisa dibuka offline karena dibuat dengan `--single-file`.

### Menentukan jumlah `SHARDS`

Jumlah shard ditentukan oleh **jumlah flow dan total durasinya**, bukan besar aplikasinya.

```
waktu tunggu ≈ overhead per shard + (total durasi semua flow ÷ SHARDS)
menit runner ≈ SHARDS × overhead + total durasi semua flow
```

- Overhead per shard (setup job, download APK, Maestro, menyalakan emulator) kira-kira 1–2 menit. Dengan cache snapshot mungkin lebih kecil, tapi belum terukur.
- Menambah shard mempercepat hasil, tapi menambah menit runner karena overhead ikut dikali. Makin banyak shard, makin kecil tambahan cepatnya.
- Cara memilih: tentukan target waktu tunggu (misalnya 10–15 menit), lalu `SHARDS ≈ total durasi flow ÷ target`. Setelah beberapa run, sesuaikan berdasarkan durasi asli tiap flow di Allure.
- Batas paralel GitHub dihitung untuk semua workflow di organisasi (Free 20 job, Team 60, Enterprise jauh lebih banyak). Jangan pasang shard sampai menghabiskan jatah job lain.
- Kalau repo-nya private, setiap shard tambahan menambah biaya overhead per run.

**Rekomendasi untuk project nyata (perkiraan 20–30 flow, termasuk edge case):** mulai dengan `SHARDS: 4`, lalu naikkan ke 5 kalau sudah mendekati 30 flow. Asumsinya flow utama sekitar 2 menit, edge case lebih pendek, rata-rata sekitar 1,5 menit, dan overhead sekitar 1,5 menit.

| Jumlah flow | Total durasi flow | SHARDS | Flow per shard | Waktu tunggu kira-kira | Menit runner |
|---|---|---|---|---|---|
| 20 | ~30 menit | 3 | 6–7 | ~12 menit | ~35 |
| 20 | ~30 menit | **4** | 5 | **~9 menit** | ~36 |
| 30 | ~45 menit | **4** | 7–8 | **~13 menit** | ~51 |
| 30 | ~45 menit | 5 | 6 | ~10,5 menit | ~52 |
| 30 | ~45 menit | 6 | 5 | ~9 menit | ~54 |

**Jangan pakai "satu shard = satu fitur".** Jumlah flow tiap fitur tidak sama (misalnya login punya 8 edge case, profil cuma 2), jadi shard fitur terbesar yang menentukan lamanya workflow. Pembagian bergiliran berdasarkan nama file yang diurutkan justru otomatis menyebar flow dari fitur yang sama ke shard berbeda, asalkan file dinamai per fitur:

```
01_login_sukses.yaml            → shard-1
02_login_password_salah.yaml    → shard-2
03_login_akun_terkunci.yaml     → shard-3
04_login_tanpa_internet.yaml    → shard-4
05_bayar_tagihan_sukses.yaml    → shard-1
```

Flow panjang dan edge case pendek jadi tercampur rata. Di Allure, pengelompokan per fitur tetap terbaca dari nama file (`subSuite`).

**Kelemahan yang diketahui:** pembagian berdasarkan **jumlah** flow, bukan durasi. Kalau ada beberapa flow yang jauh lebih lama, atur nomor urutnya supaya terbagi ke shard berbeda. Pembagian berdasarkan durasi (dari hasil run sebelumnya) bisa dibuat, tapi lebih rumit dan baru perlu kalau ketidakseimbangannya memang terasa.

---

## 6. Converter `.github/scripts/maestro_to_allure.py`

Converter ini membaca `<test-output-dir>/<timestamp>/<flow>/commands.json`, yaitu data yang sama yang
dipakai Maestro untuk report HTML-detailed, lalu menulis `<uuid>-result.json` Allure beserta
step bertingkat, status, pesan error, dan lampiran. Hanya memakai Python stdlib.

Pemetaan yang dilakukan:

| Sumber Maestro | Di Allure |
|---|---|
| Setiap entri `commands.json` | Step dengan nama yang mudah dibaca, misalnya `Tap on "Increment"`, `Assert that "1" is visible`. Step bertingkat (misalnya isi `repeat`) mengikuti `metadata.depth`. |
| `metadata.status` COMPLETED/WARNED/FAILED/SKIPPED | passed / passed / failed / skipped |
| `metadata.error` | `statusDetails.message/trace` di step dan di test |
| `takeScreenshot/<nama>.png` | Lampiran gambar di step **sebelumnya** (level yang sama); step `takeScreenshot` disembunyikan |
| `screenshots/step-NNN-*.png` (screenshot otomatis saat gagal) | Lampiran di step yang cocok |
| `logs/maestro.log` | Lampiran di level test |
| `name` dan `tags` di header flow | Judul test dan label `tag` |
| Nama file flow | Label `subSuite` (suite = `Maestro`) |
| `historyId = md5(name)` | Run berulang dengan nama yang sama dianggap retry |

Step internal `defineVariablesCommand` dan `applyConfigurationCommand` disembunyikan, kecuali kalau gagal.

```python
#!/usr/bin/env python3
"""Ubah hasil debug Maestro (commands.json) menjadi hasil Allure lengkap dengan step.

Maestro tidak punya output Allure, dan JUnit XML-nya tidak menyimpan step.
Detail per langkah ada di `<test-output-dir>/<timestamp>/<flow>/commands.json`
(data yang sama dipakai Maestro untuk laporan HTML-DETAILED).

Pemakaian:
    python3 maestro_to_allure.py <maestro-test-output-dir> <allure-results-dir> [flow.yaml ...]

Kalau file flow disebutkan, flow yang tidak punya output (mis. Maestro gagal
diinstal atau emulator crash) tetap masuk laporan sebagai "broken".
"""

import hashlib
import json
import os
import re
import shutil
import sys
import uuid

STATUS = {
    "COMPLETED": "passed",
    "WARNED": "passed",
    "FAILED": "failed",
    "SKIPPED": "skipped",
}
# Langkah internal Maestro yang tidak perlu tampil (kecuali kalau gagal).
HIDDEN = {"defineVariablesCommand", "applyConfigurationCommand"}


def selector_text(sel):
    for key in ("textRegex", "idRegex", "text", "id"):
        if sel.get(key):
            return sel[key]
    return json.dumps(sel)


def describe(kind, cmd):
    """Nama step yang mudah dibaca, mengikuti gaya laporan HTML Maestro."""
    if kind == "launchAppCommand":
        name = f'Launch app "{cmd.get("appId")}"'
        if cmd.get("clearState"):
            name += " with clear state"
        if cmd.get("stopApp") is False:
            name += " (without stopping app)"
        return name
    if kind == "assertConditionCommand":
        cond = cmd.get("condition", {})
        if "visible" in cond:
            return f'Assert that "{selector_text(cond["visible"])}" is visible'
        if "notVisible" in cond:
            return f'Assert that "{selector_text(cond["notVisible"])}" is not visible'
        return "Assert condition"
    if kind == "tapOnElement":
        return f'Tap on "{selector_text(cmd.get("selector", {}))}"'
    if kind == "repeatCommand":
        return f'Repeat {cmd.get("times", "")} times'.replace("  ", " ")
    if kind == "pressKeyCommand":
        return f'Press {cmd.get("code")} key'
    if kind == "stopAppCommand":
        return f'Stop app "{cmd.get("appId")}"'
    if kind == "inputTextCommand":
        return f'Input text "{cmd.get("text")}"'
    if kind == "takeScreenshotCommand":
        return f'Take screenshot "{cmd.get("path")}"'
    # Fallback: "scrollCommand" -> "Scroll"
    words = re.sub(r"(?<!^)(?=[A-Z])", " ", kind.removesuffix("Command"))
    return words.capitalize()


def attach(results_dir, src, name, mime):
    ext = os.path.splitext(src)[1]
    target = f"{uuid.uuid4()}-attachment{ext}"
    shutil.copy(src, os.path.join(results_dir, target))
    return {"name": name, "source": target, "type": mime}


def convert_flow(flow_dir, results_dir):
    commands = json.load(open(os.path.join(flow_dir, "commands.json")))
    screenshots = sorted(
        os.listdir(os.path.join(flow_dir, "screenshots"))
        if os.path.isdir(os.path.join(flow_dir, "screenshots"))
        else []
    )

    flow_name = os.path.basename(flow_dir)
    tags = []
    file_name = None
    root_steps, stack = [], []  # stack: (depth, step)
    failure = None
    start = stop = None

    for entry in commands:
        kind, cmd = next(iter(entry["command"].items()))
        meta = entry.get("metadata", {})
        status = STATUS.get(meta.get("status"), "skipped")

        if kind == "applyConfigurationCommand":
            flow_name = cmd.get("config", {}).get("name") or flow_name
            tags = cmd.get("config", {}).get("tags") or []
        if kind == "defineVariablesCommand":
            file_name = cmd.get("env", {}).get("MAESTRO_FILENAME")
        if kind in HIDDEN and status != "failed":
            continue

        # `- takeScreenshot: nama` di flow: tempel gambarnya ke step sebelumnya
        # (level yang sama) dan jangan tampilkan sebagai step tersendiri.
        if kind == "takeScreenshotCommand" and status != "failed":
            depth = meta.get("depth", 0)
            while stack and stack[-1][0] > depth:
                stack.pop()
            path = cmd.get("path", "")
            png = os.path.join(flow_dir, "takeScreenshot", path if path.endswith(".png") else f"{path}.png")
            if stack and os.path.isfile(png):
                stack[-1][1]["attachments"].append(attach(results_dir, png, os.path.basename(png), "image/png"))
                continue

        ts = meta.get("timestamp")
        dur = meta.get("duration") or 0
        if ts is not None:
            start = ts if start is None else min(start, ts)
            stop = ts + dur if stop is None else max(stop, ts + dur)

        step = {
            "name": describe(kind, cmd),
            "status": status,
            "stage": "finished",
            "start": ts,
            "stop": ts + dur if ts is not None else None,
            "steps": [],
            "attachments": [],
        }
        error = meta.get("error")
        if error:
            step["statusDetails"] = {
                "message": error.get("message", ""),
                "trace": error.get("debugMessage", ""),
            }
            if failure is None:
                failure = step["statusDetails"]

        # Screenshot Maestro diberi nama step-<urutan+1>-..., pasangkan ke stepnya.
        prefix = f"step-{meta.get('sequenceNumber', -2) + 1:03d}-"
        for shot in screenshots:
            if shot.startswith(prefix):
                step["attachments"].append(
                    attach(results_dir, os.path.join(flow_dir, "screenshots", shot), shot, "image/png")
                )

        depth = meta.get("depth", 0)
        while stack and stack[-1][0] >= depth:
            stack.pop()
        (stack[-1][1]["steps"] if stack else root_steps).append(step)
        stack.append((depth, step))

    statuses = []

    def collect(steps):
        for s in steps:
            statuses.append(s["status"])
            collect(s["steps"])

    collect(root_steps)
    status = "failed" if "failed" in statuses else "passed"

    attachments = []
    log = os.path.join(flow_dir, "logs", "maestro.log")
    if os.path.isfile(log):
        attachments.append(attach(results_dir, log, "maestro.log", "text/plain"))

    labels = [
        {"name": "framework", "value": "maestro"},
        {"name": "suite", "value": "Maestro"},
    ]
    if file_name:
        labels.append({"name": "subSuite", "value": file_name})
    labels += [{"name": "tag", "value": t} for t in tags]

    result = {
        "uuid": str(uuid.uuid4()),
        "historyId": hashlib.md5(flow_name.encode()).hexdigest(),
        "name": flow_name,
        "fullName": f"maestro.{file_name or flow_name}",
        "status": status,
        "stage": "finished",
        "start": start,
        "stop": stop,
        "labels": labels,
        "steps": root_steps,
        "attachments": attachments,
    }
    if failure:
        result["statusDetails"] = failure
    write_result(results_dir, result)
    return flow_name, status, file_name


def write_result(results_dir, result):
    with open(os.path.join(results_dir, f"{result['uuid']}-result.json"), "w") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)


def read_header(flow_file):
    """Ambil `name` dan `tags` dari header flow (bagian sebelum `---`)."""
    name, tags, in_tags = None, [], False
    for line in open(flow_file):
        if line.strip() == "---":
            break
        if line.startswith("name:"):
            name = line.split(":", 1)[1].strip().strip("\"'")
        in_tags = line.startswith("tags:") or (in_tags and line.lstrip().startswith("-"))
        if in_tags and line.lstrip().startswith("-"):
            tags.append(line.lstrip()[1:].strip().strip("\"'"))
    return name, tags


def write_broken(results_dir, flow_file):
    """Flow yang tidak menghasilkan output tetap dicatat di laporan."""
    file_name = os.path.splitext(os.path.basename(flow_file))[0]
    name, tags = read_header(flow_file)
    name = name or file_name
    run_url = "{}/{}/actions/runs/{}".format(
        os.environ.get("GITHUB_SERVER_URL", ""),
        os.environ.get("GITHUB_REPOSITORY", ""),
        os.environ.get("GITHUB_RUN_ID", ""),
    )
    labels = [
        {"name": "framework", "value": "maestro"},
        {"name": "suite", "value": "Maestro"},
        {"name": "subSuite", "value": file_name},
    ] + [{"name": "tag", "value": t} for t in tags]
    write_result(results_dir, {
        "uuid": str(uuid.uuid4()),
        "historyId": hashlib.md5(name.encode()).hexdigest(),
        "name": name,
        "fullName": f"maestro.{file_name}",
        "status": "broken",
        "stage": "finished",
        "labels": labels,
        "steps": [],
        "attachments": [],
        "statusDetails": {
            "message": "Flow tidak jalan: Maestro tidak menghasilkan output "
                       "(mis. Maestro gagal diinstal atau emulator bermasalah). "
                       f"Cek log job di {run_url}",
        },
    })
    return name


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    debug_dir, results_dir, flow_files = sys.argv[1], sys.argv[2], sys.argv[3:]
    os.makedirs(results_dir, exist_ok=True)
    done = set()
    for root, _, files in os.walk(debug_dir):
        if "commands.json" in files:
            name, status, file_name = convert_flow(root, results_dir)
            print(f"{status:>7}  {name}")
            done.add(file_name)
    for flow_file in flow_files:
        if os.path.splitext(os.path.basename(flow_file))[0] not in done:
            print(f"{'broken':>7}  {write_broken(results_dir, flow_file)}")
    if not done and not flow_files:
        sys.exit(f"Tidak ada commands.json di {debug_dir}")


if __name__ == "__main__":
    main()
```

**Kalau memakai command Maestro baru** (misalnya `scrollUntilVisible`, `swipe`, `eraseText`, `runFlow`):
fallback di `describe()` tetap menghasilkan nama yang cukup jelas (contoh: `Scroll until visible`).
Tambahkan cabang khusus di `describe()` hanya kalau perlu nama yang lebih jelas. Cara melihat
struktur JSON sebuah command: buka `commands.json` di artifact `maestro-debug-<flow>`.

---

## 7. Menjalankan di lokal (macOS)

```bash
# Install Maestro (kalau curl|bash diblokir, pakai brew)
brew install mobile-dev-inc/tap/maestro
export MAESTRO_CLI_NO_ANALYTICS=1

# Build APK release (sama seperti CI)
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Satu flow
maestro test .maestro/flows/02_tambah_counter.yaml

# Semua flow, filter tag
maestro test .maestro --include-tags smoke

# Paralel + headless di lokal: nyalakan beberapa emulator tanpa jendela.
# -read-only memungkinkan beberapa instance dari AVD yang sama.
emulator -avd Medium_Phone -port 5554 -read-only -no-window -no-audio -no-boot-anim -no-snapshot-save &
emulator -avd Medium_Phone -port 5556 -read-only -no-window -no-audio -no-boot-anim -no-snapshot-save &
adb -s emulator-5554 shell settings put global hide_error_dialogs 1
adb -s emulator-5556 shell settings put global hide_error_dialogs 1
maestro --device emulator-5554,emulator-5556 test .maestro --shard-split 2 \
  --format junit --output build/maestro/report.xml --test-output-dir build/maestro/results

# Coba converter + Allure di lokal
python3 .github/scripts/maestro_to_allure.py build/maestro/results build/allure-results
allure generate --single-file --clean -o build/allure-report build/allure-results  # brew install allure

# Validasi workflow sebelum commit
brew install actionlint && actionlint
```

Hal yang perlu diketahui:

- `maestro test --headless` hanya berlaku untuk web. Untuk Android, headless berarti emulator dijalankan dengan `-no-window`. Di CI, emulator-runner sudah headless.
- GitHub Actions **tidak bisa dijalankan penuh di lokal**: emulator butuh KVM/runner Linux, dan `act` tidak praktis untuk kasus ini. Cek workflow secara statis dengan `actionlint`, lalu uji sungguhan lewat push/`workflow_dispatch`.
- Di bash 3.2 bawaan macOS dengan `set -u`, array kosong dianggap unbound. Pakai pola `${arr[@]+"${arr[@]}"}`. Jangan pakai `wait` tanpa PID kalau emulator berjalan di background, karena perintah itu akan ikut menunggu emulator selamanya.

---

## 8. Troubleshooting (semua pernah terjadi)

| Gejala | Penyebab | Solusi |
|---|---|---|
| Flow gagal acak di emulator yang baru boot, dan screenshot menunjukkan dialog "Google Play Store keeps stopping" | Image dengan Play Store dan dialog crash sistem | `target: google_apis` + `adb shell settings put global hide_error_dialogs 1` sebelum test |
| Elemen pertama tidak ditemukan atau timeout setelah launch | Launch pertama di emulator yang baru boot lambat | `extendedWaitUntil` dengan `timeout: 60000` setelah `launchApp` |
| Laporan Allure kosong (0 test) | Hasil berada di subfolder; Allure hanya membaca level teratas | Atur path upload/download agar file berada langsung di folder hasil |
| Allure muncul tetapi tanpa step | Sumbernya JUnit XML, yang tidak punya step | Pakai converter `commands.json` → Allure |
| Flow yang gagal/error tidak muncul di Allure (report terlihat hijau) | Download installer Maestro putus (`curl: (56) Connection reset`), installer tetap exit 0, `maestro` tidak ada (exit 127), jadi tidak ada `commands.json` | Install Maestro dengan retry + cek `maestro --version`; converter menerima daftar flow dan menulis flow tanpa output sebagai **broken** |
| Tap terlewat sehingga counter/hasil kurang satu, dan di `maestro.log` ada tap yang menunggu "settled hierarchy" puluhan detik | Emulator sempat macet (sering terjadi tak lama setelah boot); tap terkirim saat UI belum siap | Flaky emulator, bukan bug app; jalankan ulang. Kalau sering, tambahkan assert setelah tap penting supaya Maestro menunggu UI berubah |
| "Kok hasilnya sama saja?" setelah fix | Run yang dilihat adalah run lama (misalnya run `push: main` dari merge sebelumnya), bukan commit fix | Cek SHA commit di run sebelum menyimpulkan |
| Maestro tidak jalan sama sekali setelah push ke `uat` | `maestro.yml` belum ada di `main`, `name` workflow review tidak cocok, atau review tidak punya trigger push `uat` | Merge workflow ke `main`, samakan `workflows:` dengan `name:` review, dan tambahkan `push: branches: [uat]` di review |
| `actionlint` SC2012 | Memakai `ls` untuk listing | Pakai `find` |
| Perintah multi-baris di `script:` emulator-runner gagal | Setiap baris dijalankan sebagai shell terpisah | Tulis satu perintah per baris |

---

## 9. Checklist adaptasi ke proyek nyata

Saat menerapkan ke proyek nyata, sesuaikan hal-hal berikut. Cek repo dulu dan tanya user hanya kalau tidak bisa dipastikan:

- [ ] `appId` di setiap flow = `applicationId` di `android/app/build.gradle(.kts)`. Kalau ada flavor, suffix-nya ikut, misalnya `com.company.app.dev`.
- [ ] `flutter-version` di workflow sama dengan versi proyek (cek `.fvmrc`, `pubspec.yaml` environment, atau tanya user).
- [ ] Perintah build. Kalau ada flavor/entrypoint: `flutter build apk --release --flavor uat -t lib/main_uat.dart`. **Path APK ikut berubah**, misalnya `build/app/outputs/flutter-apk/app-uat-release.apk`. Update `path` upload dan nama file di `adb install`.
- [ ] Untuk `--dart-define` / env rahasia, pakai GitHub Secrets (`${{ secrets.X }}`). Jangan hardcode.
- [ ] Kredensial login untuk test: kirim lewat `maestro test -e USERNAME=${{ secrets.E2E_USER }} -e PASSWORD=...`, lalu pakai `${USERNAME}` di flow.
- [ ] Teks selector disesuaikan dengan UI nyata. Kalau aplikasi multi-bahasa, pertimbangkan `Semantics(identifier:)` + `id:` agar tidak bergantung teks.
- [ ] Ganti teks di `extendedWaitUntil` dengan elemen yang pasti muncul di layar pertama (splash/login/home).
- [ ] Flow yang butuh login: buat sub-flow `.maestro/subflows/login.yaml` lalu panggil dengan `runFlow`. Jangan masukkan subflow ke `flows/*` supaya tidak ikut matrix.
- [ ] Atur `SHARDS` (untuk 20–30 flow mulai dari 4; lihat "Menentukan jumlah `SHARDS`" di bagian 5). Nama file flow dibuat per fitur (`NN_<fitur>_<skenario>.yaml`), unik, dan tanpa spasi.
- [ ] `timeout-minutes` disesuaikan dengan durasi flow terpanjang.
- [ ] Jalankan `actionlint`, lalu **commit lokal saja**. User yang push.

---

## 10. Ringkasan satu paragraf (untuk konteks cepat)

E2E Flutter Android memakai **Maestro**, dengan satu file YAML per test case di `.maestro/flows/`.
Setiap flow mandiri (`clearState`), menunggu layar pertama hingga 60 detik, dan mengambil
`takeScreenshot` setelah setiap step. CI memakai **GitHub Actions tanpa shell script**. Job `build`
membuat APK release sekali dan membagi flow ke `SHARDS` shard. Job `maestro` adalah matrix satu job per shard,
masing-masing dengan emulator headless `reactivecircus/android-emulator-runner@v2` (API 34,
`google_apis`, KVM, `hide_error_dialogs`). Hasil `commands.json` dikonversi menjadi hasil
**Allure** oleh `.github/scripts/maestro_to_allure.py` (step + screenshot per step + log). Job
`allure-report` menggabungkan semua flow menjadi **satu** report Allure `--single-file`
(artifact `allure-report-maestro`) dan menulis ringkasan ke Job Summary. Trigger: push ke `uat` yang sudah lolos workflow `PR AI Code Review` (via `workflow_run`), dan manual. Perubahan
harus minimal, commit lokal saja, dan user yang push.
