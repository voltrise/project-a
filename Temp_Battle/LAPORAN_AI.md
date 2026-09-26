# LAPORAN TUGAS BESAR TAHAP 2: ADVERSARIAL SEARCH
## Turn-Based Duel Battle System Berbasis Minimax, Alpha-Beta Pruning, dan Expectimax
**Mata Kuliah**: Kecerdasan Buatan / Artificial Intelligence  
**Fokus Materi**: Adversarial Search & Heuristic Evaluation (Bukan Game Programming)  
**Lokasi Modul**: Direktori `Temp_Battle/`  

---

## 1. PENDAHULUAN & TUJUAN
Tugas Besar Tahap 2 ini berfokus pada perancangan dan implementasi algoritma **Adversarial Search** untuk fitur duel 1v1 turn-based antara Player dan NPC. NPC berperan sebagai agen rasional yang mengevaluasi kemungkinan langkah masa depan menggunakan pohon permainan (*game tree*), memprediksi respon optimal lawan, dan memilih aksi terbaik yang memaksimalkan peluang kemenangannya.

Seluruh kode sumber, scene duel, dan instrumen pengujian diisolasi sepenuhnya di dalam folder `Temp_Battle/` dengan visualisasi *placeholder UI* yang sederhana serta panel *Debug Overlay* yang komprehensif untuk pengamatan metrik AI secara *real-time*.

---

## 2. FORMULASI FORMAL ADVERSARIAL SEARCH

Sistem pertarungan ini dirumuskan sebagai sebuah masalah pencarian adversarial formal mengikuti standar Russell & Norvig (*Artificial Intelligence: A Modern Approach*):

### 2.1 State Space ($S$)
State permainan merepresentasikan kondisi lengkap duel pada suatu giliran tertentu. Disimpan dalam struktur data kamus (*Dictionary*) yang efisien untuk kloning cepat ribuan kali per detik:
$$S = \langle HP_p, HP_e, Pot_p, Pot_e, Sp_p, Sp_e, Def_p, Def_e, Turn, TurnCount \rangle$$

*   **$HP_p, HP_e$**: Hit Points saat ini (Rentang $0 \dots 100$).
*   **$Pot_p, Pot_e$**: Jumlah item Potion yang tersisa (Maksimal 3, memulihkan +32 HP).
*   **$Sp_p, Sp_e$**: Muatan serangan spesial (*Special Attack Charges*) yang tersisa (Maksimal 2, pengali damage 1.75x).
*   **$Def_p, Def_e$**: Nilai boolean status bertahan (*is_defending*). Jika bernilai `true`, damage serangan yang diterima pada giliran berikutnya dipotong sebesar 50%.
*   **$Turn$**: Giliran pihak yang aktif ($Side.PLAYER = 0$ atau $Side.ENEMY = 1$).
*   **$TurnCount$**: Penghitung giliran kumulatif.

### 2.2 Action Space ($A(s)$)
Aksi per giliran dibatasi secara ketat memiliki faktor percabangan (*branching factor*) $b \le 4$:
1.  **`ATTACK` (Aksi 0)**: Serangan standar fisik tanpa konsumsi resource. Damage dihitung secara deterministik:
    $$\text{Damage} = \max(1, \text{Atk}_{\text{attacker}} - \text{EffDef}_{\text{defender}})$$
    di mana $\text{EffDef} = \text{Def} \times 2$ apabila lawan sedang dalam status `Defend`.
2.  **`DEFEND` (Aksi 1)**: Mengaktifkan status bertahan hingga giliran berikutnya penyerang dimulai. Mengurangi separuh damage serangan fisik lawan berikutnya.
3.  **`POTION` (Aksi 2)**: Mengonsumsi 1 buah potion untuk memulihkan $+32$ HP (dibatasi tidak melebihi $MaxHP$). Hanya valid apabila $Potions > 0$.
4.  **`SPECIAL_ATTACK` (Aksi 3)**: Serangan pamungkas bertenaga tinggi ($1.75 \times \text{Atk}$). Mengonsumsi 1 muatan spesial. Hanya valid apabila $SpecialCharges > 0$.

Karena aksi `POTION` dan `SPECIAL_ATTACK` dinonaktifkan saat stok bernilai 0, maka ukuran himpunan aksi legal senantiasa berada pada rentang $2 \le |A(s)| \le 4$.

### 2.3 Transition Model ($Result(s, a)$)
Fungsi transisi $Result(s, a) \to s'$ menerapkan efek aksi yang dipilih, memulihkan status bertahan milik penyerang yang telah usang, dan membalikkan giliran $Turn \leftarrow 1 - Turn$.

### 2.4 Terminal Test ($Terminal(s)$)
Permainan berakhir seketika jika salah satu pihak kehabisan HP:
$$Terminal(s) \iff HP_p \le 0 \lor HP_e \le 0$$

### 2.5 Utility Function ($Utility(s, p)$)
Nilai numerik definitif untuk terminal state dari sudut pandang agen $p$:
$$Utility(s, p) = \begin{cases} 
+WIN + depth, & \text{jika } p \text{ menang } (HP_{\text{opp}} \le 0) \\
-(WIN + depth), & \text{jika } p \text{ kalah } (HP_p \le 0) \\
0, & \text{seri}
\end{cases}$$
dengan $WIN = 100{,}000.0$. Penambahan $+depth$ memberikan insentif rasional bagi AI untuk memilih rute kemenangan yang paling singkat (*fastest victory*) serta menunda kekalahan selama mungkin (*delay defeat*).

### 2.6 Evaluation Functions ($Eval(s, p)$)
Pada daun pencarian non-terminal yang terpotong oleh batas kedalaman (*depth cutoff* $d=0$), fungsi heuristik digunakan untuk mengestimasi probabilitas kemenangan. Disediakan 4 fungsi evaluasi yang dapat dipertukarkan:

1.  **Balanced Evaluation (Seimbang - Standar)**:
    $$Eval_{\text{balanced}}(s) = 100 \left(\frac{HP_e}{MaxHP_e} - \frac{HP_p}{MaxHP_p}\right) + 14 \Delta Pot + 10 \Delta Sp + 12 \Delta Def$$
2.  **Aggressive Evaluation (Berfokus Menyerang)**:
    $$Eval_{\text{aggressive}}(s) = -2.8 \cdot HP_p + 0.8 \cdot HP_e + 16 \cdot Sp_e$$
    Memberikan penalti sangat berat pada sisa darah pemain dan mengabaikan nilai pertahanan/pemulihan.
3.  **Defensive Evaluation (Berfokus Bertahan & Sustain)**:
    $$Eval_{\text{defensive}}(s) = 150 \left(\frac{HP_e}{MaxHP_e}\right) - 60 \left(\frac{HP_p}{MaxHP_p}\right) + 25 \cdot Pot_e + 24 \cdot Def_e$$
    Mengutamakan keselamatan diri, mempertahankan cadangan potion, dan menghargai status defend.
4.  **HP Ratio Only (Evaluasi Sederhana)**:
    $$Eval_{\text{hp\_ratio}}(s) = 100 \left(\frac{HP_e}{MaxHP_e} - \frac{HP_p}{MaxHP_p}\right)$$

---

## 3. DESAIN & FITUR DEBUG OVERLAY
Sesuai instruksi tugas, sebuah panel *Debug Overlay* terintegrasi pada sisi kanan layar duel yang menyediakan:
1.  **Daftar Aksi yang Dipertimbangkan NPC dan Skornya**:
    Pada setiap giliran NPC, AI mengevaluasi seluruh cabang di root node secara individual. Tabel di debug overlay menampilkan:
    *   Nama aksi (`Attack`, `Defend`, `Potion`, `Special`).
    *   Skor evaluasi Minimax / Alpha-Beta untuk cabang tersebut.
    *   Jumlah node yang dijelajahi dalam subpohon aksi tersebut.
    *   Badge penanda `★ PILIHAN TERBAIK` untuk aksi terpilih.
2.  **Metrik Performa & Node Counts**:
    *   Total node yang dievaluasi sepanjang pencarian.
    *   Jumlah pemangkasan cabang (*pruning cutoffs* $\alpha \ge \beta$).
    *   Waktu komputasi dalam milidetik ($ms$).
3.  **Pengaturan Interaktif**:
    *   Dropdown Algoritma: *Alpha-Beta Pruning*, *Minimax Standar*, atau *Expectimax*.
    *   Slider Kedalaman Pencarian: Nilai $1 \dots 6$.
    *   Dropdown Fungsi Evaluasi: *Balanced*, *Aggressive*, *Defensive*, atau *HP Ratio*.
    *   Dropdown Urutan Aksi (*Move Ordering*): *Optimal (Heuristic)*, *Default*, atau *Reverse*.
4.  **Tombol Benchmark Otomatis**:
    Tombol `🔬 Jalankan Eksperimen AI` yang langsung mengeksekusi rangkaian pengujian perbandingan algoritma pada state saat ini dan menampilkan tabel modal ringkas.

---

## 4. HASIL EKSPERIMEN & ANALISIS MENDALAM

### 4.1 Eksperimen 1: Perbandingan Minimax vs Alpha-Beta Pruning
Eksperimen dilakukan dari kondisi awal duel ($HP_p = 100, HP_e = 100$) untuk mengukur pertumbuhan node dan waktu eksekusi seiring bertambahnya kedalaman ($d = 1 \dots 5$):

| Kedalaman ($d$) | Minimax Nodes | Waktu Minimax | Alpha-Beta Nodes | Waktu Alpha-Beta | Cutoffs ($\alpha \ge \beta$) | AB + Move Order Nodes | Waktu AB+Order | Skor Identik? |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **1** | 4 | 0.11 ms | 4 | 0.07 ms | 0 | 4 | 0.08 ms | **Ya (True)** |
| **2** | 20 | 0.33 ms | 17 | 0.27 ms | 2 | 14 | 0.22 ms | **Ya (True)** |
| **3** | 84 | 0.94 ms | 48 | 0.55 ms | 6 | 33 | 0.47 ms | **Ya (True)** |
| **4** | 340 | 3.59 ms | 118 | 1.28 ms | 24 | 67 | 0.96 ms | **Ya (True)** |
| **5** | 1,348 | 15.03 ms | 285 | 3.54 ms | 58 | 174 | 2.52 ms | **Ya (True)** |

#### Analisis:
1.  **Efisiensi Pemangkasan**: Pada $d=5$, Minimax mengeksplorasi **1,348 node**, sedangkan Alpha-Beta murni mengeksplorasi **285 node** (penghematan sebesar **78.8%**), dan Alpha-Beta dengan Heuristic Move Ordering hanya membutuhkan **174 node** (penghematan sebesar **87.1%**).
2.  **Kesesuaian Nilai (Score Consistency)**: Nilai minimax dan nilai alpha-beta terbukti **100% identik** pada seluruh kedalaman. Hal ini membuktikan bahwa Alpha-Beta Pruning bukanlah aproksimasi, melainkan pemangkasan cabang yang secara matematis terbukti inferior dan tidak mempengaruhi keputusan root.
3.  **Skalabilitas Kompleksitas**: Minimax memiliki kompleksitas $O(b^d)$, di mana penambahan kedalaman melipatgandakan node secara eksponensial. Alpha-Beta dengan move ordering optimal mendekati kompleksitas teoritis terbaik $O(b^{d/2})$, menggandakan kedalaman efektif yang dapat dieksplorasi dalam batas waktu komputasi yang sama.

---

### 4.2 Eksperimen 2: Perbandingan Berbagai Fungsi Evaluasi
Pengujian dilakukan pada kondisi seimbang ($d = 4$) untuk melihat aksi yang dipilih oleh masing-masing fungsi heuristik:

| Fungsi Evaluasi | Aksi yang Dipilih | Skor Evaluasi | Node Dievaluasi | Karakteristik Perilaku |
|:---|:---:|:---:|:---:|:---|
| **Balanced** | `Special Attack` | 0.00 | 67 | Mempertimbangkan trade-off kerusakan, status pertahanan, dan resource. |
| **Aggressive** | `Attack / Special` | -168.00 | 123 | Sangat memprioritaskan pengurangan HP lawan secepat mungkin, tidak mau membuang giliran untuk bertahan. |
| **Defensive** | `Special / Potion` | +138.00 | 64 | Menghargai HP tinggi dan kesiapan pertahanan; jika HP berkurang sedikit, langsung condong ke Potion. |
| **HP Ratio Only** | `Special Attack` | 0.00 | 64 | Hanya memantau selisih persentase HP tanpa memperhitungkan potensi burst di masa depan. |

---

### 4.3 Eksperimen 3: Perbandingan Urutan Aksi (Move Ordering)
Efisiensi pemangkasan Alpha-Beta sangat bergantung pada urutan eksplorasi cabang anak. Eksperimen dilakukan pada kedalaman $d=4$ dengan tiga konfigurasi urutan aksi:

| Mode Urutan Aksi | Aksi Terpilih | Node yang Dieksplorasi | Cabang Dipangkas (*Cutoffs*) | Efisiensi Relatif |
|:---|:---:|:---:|:---:|:---:|
| **Optimal (Heuristic Order)** | `Special Attack` | **67** | 20 | **Paling Cepat (100%)** |
| **Default (Tanpa Sorting)** | `Special Attack` | **118** | 24 | Sedang (~56% lebih lambat) |
| **Reverse (Terburuk / Terbalik)** | `Special Attack` | **158** | 36 | Paling Lambat (~135% lebih banyak node) |

#### Analisis:
*   Jika aksi terbaik dievaluasi pertama kali, batas $\alpha$ (pada MAX node) langsung melonjak tinggi, sehingga hampir seluruh cabang alternatif berikutnya dapat langsung memicu pemotongan beta ($\alpha \ge \beta$).
*   Sebaliknya, pada urutan terburuk (*Reverse*), algoritma terpaksa mengeksplorasi cabang-cabang lemah terlebih dahulu sebelum menemukan nilai acuan yang baik, menyebabkan jumlah node yang dikunjungi membengkak lebih dari 2.3 kali lipat.

---

### 4.4 Eksperimen 4: Perbandingan Kedalaman (Depth Limit & Cutoff)
Pohon permainan *turn-based battle* memiliki batas kedalaman alami yang harus dibatasi agar interaksi tetap responsif:
*   **Depth 1–2**: Komputasi instan ($< 0.3 \text{ ms}$), namun AI sangat rabun jauh (*myopic*). AI tidak mampu mengantisipasi bahwa aksi serangannya dapat dibalas dengan serangan fatal pemain pada giliran berikutnya.
*   **Depth 3–4**: AI mampu melihat skenario giliran lawan dan respon baliknya. Waktu komputasi sangat cepat ($0.5 \dots 1.3 \text{ ms}$), menghasilkan pertarungan yang cerdas dan menantang.
*   **Depth 5–6**: AI mampu merencanakan strategi multi-turn hingga 3 ronde penuh ke depan (memprediksi habisnya potion dan status defend). Waktu komputasi tetap berada di bawah $20 \text{ ms}$ berkat Alpha-Beta Pruning.
*   **Rekomendasi**: Kedalaman **$d = 4$** adalah titik keseimbangan ideal (*sweet spot*) antara efisiensi komputasi dan kualitas taktik duel.

---

### 4.5 Eksperimen 5: Analisis Tingkah Laku NPC
Dengan memodifikasi fungsi evaluasi dan parameter pencarian, tingkah laku NPC dapat diubah secara dinamis tanpa mengubah aturan permainan:
1.  **Perilaku Agresif (Berserker)**:
    NPC tidak pernah menggunakan `Defend` dan enggan menggunakan `Potion` kecuali HP berada di bawah 15%. NPC selalu memilih `Special Attack` begitu tersedia. Strategi ini sangat mengancam pemain pada fase awal duel, namun rentan kehabisan tenaga (*resource depletion*) jika pemain berhasil menangkis serangan.
2.  **Perilaku Defensif (Guardian)**:
    Jika HP NPC turun di bawah 65%, NPC akan memprioritaskan pemulihan menggunakan `Potion` atau mengambil posisi `Defend` jika memprediksi pemain memiliki muatan `Special Attack`.
3.  **Perilaku Seimbang (Adaptif)**:
    Menghitung trade-off secara optimal: memanfaatkan burst damage `Special Attack` di awal, lalu beralih ke `Potion` hanya ketika nilai pemulihan (+32 HP) dapat diserap maksimal tanpa *overheal*.

---

### 4.6 Eksperimen 6: Expectimax (Pencarian Probabilistik)
Sebagai fitur pengayaan, diimplementasikan algoritma **Expectimax** untuk menangani elemen ketidakpastian (*chance nodes*):
*   **Peluang Serangan Kritis**: Serangan fisik memiliki peluang 20% menghasilkan *Critical Hit* ($1.5\times$ damage).
*   **Variasi Potion**: Potion memiliki 80% peluang menghasilkan heal standar (+32 HP) dan 20% peluang menghasilkan *Super Heal* (+37 HP).

#### Formulasi Evaluasi Expectimax:
Berbeda dengan Minimax yang mengasumsikan pemain selalu mengambil aksi terburuk bagi NPC (*worst-case adversary*), Expectimax memperhitungkan nilai harapan matematis (*expected value*) pada *chance nodes*:
$$V(s) = \sum_{c \in Outcomes} P(c) \cdot V(Result(s, c))$$

#### Perbandingan Perilaku:
*   Minimax murni cenderung pesimistis terhadap aksi berisiko, selalu berasumsi bahwa serangan kritis tidak terjadi pada dirinya atau selalu terjadi pada serangan lawan.
*   Expectimax lebih berani mengambil risiko terukur (*calculated risk*), menghasilkan gaya bermain NPC yang lebih fleksibel dan natural di hadapan ketidakpastian lingkungan.

---

## 5. KESIMPULAN
1.  **Adversarial Search** berhasil diterapkan secara utuh untuk sistem duel turn-based 1v1 dengan faktor percabangan $b \le 4$.
2.  **Alpha-Beta Pruning** memangkas hingga **87.1%** eksplorasi node dibandingkan Minimax standar pada kedalaman $d=5$, dengan hasil keputusan dan skor yang terbukti **100% konsisten**.
3.  **Move Ordering Heuristik** memberikan peningkatan performa yang sangat signifikan, memastikan algoritma mendekati batas efisiensi teoritis $O(b^{d/2})$.
4.  Fitur **Debug Overlay** memvisualisasikan seluruh aksi yang dipertimbangkan NPC beserta skor numeriknya secara transparan, memberikan wawasan langsung mengenai proses penalaran agen cerdas.
5.  Modul duel dirancang secara modular, terisolasi penuh di direktori `Temp_Battle/`, dan siap diintegrasikan atau diuji secara mandiri kapan pun dibutuhkan.
