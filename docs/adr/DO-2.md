# DO-2: Broj VM-ova i raspored komponenti

Status: prihvaceno

## Kontekst
AO-6 trazi tri mrezno izolovana segmenta (web, app, db) s vlastitim podmrezama.
Nacin izvedbe je slobodan (DO-2), a DNS moze biti na zasebnoj ili zajednickoj VM.

## Razmotrene opcije
1. Opcija A: jedna VM, segmenti kao Docker mreze s fiksnim podmrezama (prosirenje s3/p4).
2. Opcija B: po jedna VM za svaki segment na libvirt route mrezama; host usmjerava
   izmedju njih; DNS na zasebnoj VM.

## Odluka
Opcija B: VM web, VM app, VM db (svaka na svojoj route mrezi) + VM dns + VM llm.
Host je ruter izmedju segmenata; saobracaj koji smije prelaziti segmente propisuje
nftables na hostu i vatrozidi na VM-ovima.

## Obrazlozenje i posljedice
Opcija A bi kontejnere ostavila na Docker mrezama, pa bi DNS imena slojeva pokazivala
na istu VM adresu, a razlikovala bi se samo po portu; AO-7 (adresiranje iskljucivo
imena, po sloju) time slabi. Opcija B daje svakom sloju vlastitu adresu u vlastitoj
podmrezi, pa BIND zona ima smisla po sloju, a izolacija se dokazuje na stvarnom
ruteru. Cijena: vise VM-ova i host konfiguracija (ip_forward + nftables), sto je
dokumentovano i automatizovano.
