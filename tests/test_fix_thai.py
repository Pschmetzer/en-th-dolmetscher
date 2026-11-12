import pytest

from dolmetscher import fix_thai


@pytest.mark.parametrize("src, krub, ka", [
    ("สวัสดีครับ/ค่ะ", "สวัสดีครับ", "สวัสดีค่ะ"),
    ("สวัสดีค่ะ / ครับ", "สวัสดีครับ", "สวัสดีค่ะ"),
    ("ไปไหนครับ/คะ", "ไปไหนครับ", "ไปไหนคะ"),
    ("ผม/ฉันหิว", "ผมหิว", "ฉันหิว"),
    ("ฉัน / ผมหิวครับ/ค่ะ", "ผมหิวครับ", "ฉันหิวค่ะ"),
    ("ขอบคุณ", "ขอบคุณ", "ขอบคุณ"),
])
def test_fix_thai(src, krub, ka):
    assert fix_thai(src, "krub") == krub
    assert fix_thai(src, "ka") == ka
