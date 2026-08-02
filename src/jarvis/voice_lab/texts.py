"""Fixed evaluation texts for the Voice Lab (brief §6.3–§6.4).

The primary spoken output of the system is British English (language policy,
brief §7 as amended). The Norwegian text remains part of the test set because
the voice must (a) keep the same identity if Preben explicitly requests a
Norwegian reply and (b) pronounce Norwegian names correctly inside English
sentences.
"""

TEST_TEXT_EN = (
    "Good evening. Network telemetry is stable across most of the site. "
    "Two access points are above eighty percent channel utilization, but no "
    "configuration has been changed. I have prepared a read-only comparison "
    "of channels one, six and eleven, including signal-to-noise ratio, "
    "retries and client count. The report is ready when you are. I have also "
    "checked tomorrow's schedule. Fortunately, nothing requires world "
    "domination before breakfast."
)

TEST_TEXT_NO = (
    "God ettermiddag, Preben. Nettverket er stabilt i de fleste områdene. "
    "To aksesspunkter ligger over åtti prosent kanalutnyttelse, men jeg har "
    "ikke endret konfigurasjonen. Jeg har laget en skrivebeskyttet "
    "sammenligning av kanal én, seks og elleve, med signalstyrke, "
    "signal-til-støy-forhold, pakketap og antall klienter. Rapporten er "
    "klar. Jeg har også kontrollert morgendagens avtaler."
)

# Norwegian proper nouns inside an English sentence — the core case of the
# amended language policy.
TEST_TEXT_MIXED = (
    "The uplink at Marivold is stable. Paradisbukta and Beverdalen report "
    "normal client counts, while the access point at Golanhøyden shows "
    "eighty-six percent channel utilization on channel eleven."
)

STRESS_ITEMS = [
    "192.168.10.254",
    "0C:8D:DB:4A:91:E3",
    "VLAN 42",
    "Tuesday 14 October at 07:45",
    "+47 912 34 567",
    "12 480 kroner",
    "ExtremeCloud IQ",
    "Hikvision",
    "MikroTik",
    "Home Assistant",
    "PostgreSQL",
    "Claude Fable 5",
    "GPT-5.6 Sol",
]
