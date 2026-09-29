"""背包自動整理與堆疊合併（inventory consolidation）。

規則
----
1. ``stackable`` 為真且 ``id`` 相同的物品合併成一格。
2. 每格不超過 ``max_stack``；溢出時先填滿當前格，餘量另開新格，總量守恆。
3. ``stackable`` 為假的物品各自保留獨立格子，即使 ``id`` 或 ``durability``
   完全相同也絕不合併。
4. 有效物品靠前、``None`` 靠後，且輸出長度恆等於輸入長度。

約束
----
* 不修改傳入的 list 與 dict，一律先複製再回傳新結構。
* ``stackable`` 缺漏時視為不可堆疊（安全預設）。
* 單一來源格若本身已超過 ``max_stack``，拆分後格子數會超出原長度；此時
  仍以「總長度不變 + 總量守恆」為硬約束，把尾端剩餘併回前一格，該格
  允許超出 ``max_stack``（見 main 中的 test_oversized_single_slot_keeps_length）。

執行 ``python inventory.py`` 會跑完整邊界測試。
"""

from __future__ import annotations

from typing import Any, Iterable

__all__ = ["consolidate_inventory"]


def _find_merge_pair(packed: list[dict[str, Any]]) -> tuple[int, int] | None:
    """回傳最靠後可合併的「同 id 且皆可堆疊」配對 (i, j)；找不到回傳 None。"""
    for j in range(len(packed) - 1, 0, -1):
        if not packed[j].get("stackable", False):
            continue
        for i in range(j):
            if packed[i].get("stackable", False) and packed[i]["id"] == packed[j]["id"]:
                return i, j
    return None


def consolidate_inventory(
    inventory: list[dict[str, Any] | None],
    max_stack: int = 99,
) -> list[dict[str, Any] | None]:
    """整理背包：合併可堆疊物品、壓縮空格，並保持總長度與總數量不變。

    合併順序採「首次出現順序」：先到先得，補入既有的同 id 空格，餘量才開新格。
    """
    if isinstance(max_stack, bool) or not isinstance(max_stack, int):
        raise TypeError("max_stack 必須是 int")
    if max_stack < 1:
        raise ValueError("max_stack 必須 >= 1")

    size = len(inventory)
    packed: list[dict[str, Any]] = []
    # item id -> 該 id 在 packed 中的「未滿格」索引，避免重複維護數量
    open_slots: dict[str, list[int]] = {}

    for item in inventory:
        if item is None:
            continue
        if not isinstance(item, dict):
            raise TypeError(f"背包元素必須是 dict 或 None，得到 {type(item).__name__}")

        count = item.get("count", 1)
        if isinstance(count, bool) or not isinstance(count, int):
            raise TypeError(f"count 必須是 int，得到 {type(count).__name__}")
        if count < 0:
            raise ValueError(f"count 不可為負：{count}")

        if "id" not in item:
            raise ValueError("物品缺少 id")

        # count == 0 視為空堆，丟棄（不佔格子、不影響總量）
        if count == 0:
            continue

        base = dict(item)  # 複製：不污染呼叫端

        if not item.get("stackable", False):
            # 不可堆疊：原樣保留一格，durability 不同也各自獨立
            packed.append(base)
            continue

        remaining = count
        indices = open_slots.setdefault(item["id"], [])

        # 先補既有的未滿格（回寫到 packed 中對應的 dict）
        cursor = 0
        while remaining > 0 and cursor < len(indices):
            slot = packed[indices[cursor]]
            room = max_stack - slot["count"]
            if room <= 0:
                cursor += 1
                continue
            take = room if room < remaining else remaining
            slot["count"] += take
            remaining -= take

        # 仍有剩餘 -> 開新格
        while remaining > 0:
            take = max_stack if max_stack < remaining else remaining
            packed.append({**base, "count": take})
            indices.append(len(packed) - 1)
            remaining -= take

    while len(packed) > size:
        # 硬約束優先：長度與「每個 id 的總量」都不能變，只能把尾端同 id 的
        # 可堆疊格併回前面同 id 的可堆疊格（該格因此可能超出 max_stack）。
        # 绝不碰不可堆疊的格子。
        pair = _find_merge_pair(packed)
        if pair is None:
            # 不可達：格子數變多只可能源自同 id 超載格的拆分，必有配對可合
            raise ValueError("無法在維持背包長度下完成合併")
        i, j = pair
        packed[i]["count"] += packed[j]["count"]
        del packed[j]

    packed.extend([None] * (size - len(packed)))
    return packed


# --------------------------------------------------------------------------
# 測試
# --------------------------------------------------------------------------

_CASES: list = []


def case(fn):
    _CASES.append(fn)
    return fn


def total(items: Iterable[dict | None]) -> int:
    return sum(i["count"] for i in items if i is not None)


def slots(items: Iterable[dict | None]) -> list[tuple]:
    """壓成可比對的 tuple：可堆疊看 (id, count)，不可堆疊看 (id, count, durability)。"""
    out = []
    for i in items:
        if i is None:
            continue
        if i.get("stackable", False):
            out.append((i["id"], i["count"]))
        else:
            out.append((i["id"], i["count"], i.get("durability")))
    return out


def layout(items: Iterable[dict | None]) -> list[tuple | None]:
    """與原長度一致的對照表，None 會保留在序列中。"""
    out: list[tuple | None] = []
    for i in items:
        if i is None:
            out.append(None)
        elif i.get("stackable", False):
            out.append((i["id"], i["count"]))
        else:
            out.append((i["id"], i["count"], i.get("durability")))
    return out


@case
def test_basic_overflow_split():
    inv = [None, {"id": "potion_hp", "count": 70, "stackable": True},
           {"id": "potion_hp", "count": 50, "stackable": True}, None]
    r = consolidate_inventory(inv)
    assert len(r) == 4, r
    assert layout(r) == [("potion_hp", 99), ("potion_hp", 21), None, None], r
    assert total(r) == 120


@case
def test_equipment_never_merges():
    inv = [{"id": "iron_sword", "count": 1, "stackable": False, "durability": 85},
           {"id": "iron_sword", "count": 1, "stackable": False, "durability": 100},
           {"id": "iron_sword", "count": 1, "stackable": False, "durability": 85}]
    r = consolidate_inventory(inv)
    assert len(r) == 3, r
    assert slots(r) == [("iron_sword", 1, 85), ("iron_sword", 1, 100), ("iron_sword", 1, 85)], r
    assert total(r) == 3


@case
def test_equipment_keeps_order_and_mixed_inventory():
    inv = [{"id": "iron_sword", "count": 1, "stackable": False, "durability": 100},
           {"id": "potion_hp", "count": 30, "stackable": True},
           {"id": "iron_sword", "count": 1, "stackable": False, "durability": 85},
           {"id": "potion_hp", "count": 80, "stackable": True},
           None]
    r = consolidate_inventory(inv)
    assert len(r) == 5, r
    # 首次出現順序：sword(100) -> potion 補滿 99 -> sword(85) -> 溢出 11
    assert layout(r) == [("iron_sword", 1, 100), ("potion_hp", 99),
                         ("iron_sword", 1, 85), ("potion_hp", 11), None], r


@case
def test_non_adjacent_merge():
    inv = [{"id": "ore", "count": 10, "stackable": True},
           {"id": "sword", "count": 1, "stackable": False},
           {"id": "ore", "count": 10, "stackable": True},
           {"id": "ore", "count": 10, "stackable": True}]
    r = consolidate_inventory(inv)
    assert layout(r) == [("ore", 30), ("sword", 1, None), None, None], r


@case
def test_merge_frees_slot_exactly():
    # 50 + 49 = 99 -> 剛好一格，釋放一格
    inv = [{"id": "ore", "count": 50, "stackable": True},
           {"id": "ore", "count": 49, "stackable": True}]
    r = consolidate_inventory(inv)
    assert layout(r) == [("ore", 99), None], r
    assert len(r) == 2


@case
def test_exact_multiple_and_zero_count():
    inv = [{"id": "ore", "count": 33, "stackable": True},
           {"id": "ore", "count": 33, "stackable": True},
           {"id": "ore", "count": 33, "stackable": True},
           {"id": "ore", "count": 0, "stackable": True},
           {"id": "broken_sword", "count": 0, "stackable": False}]
    r = consolidate_inventory(inv)
    # count == 0 視為空堆：可堆疊與不可堆疊都丟棄，不佔格子
    assert layout(r) == [("ore", 99), None, None, None, None], r
    assert total(r) == 99


@case
def test_custom_max_stack():
    inv = [{"id": "ore", "count": 7, "stackable": True},
           {"id": "ore", "count": 7, "stackable": True},
           {"id": "ore", "count": 7, "stackable": True}]
    r = consolidate_inventory(inv, max_stack=10)
    assert layout(r) == [("ore", 10), ("ore", 10), ("ore", 1)], r

    # 每格 1 個：總量 21 遠超 3 格 -> 依規則折疊同 id 格，長度與總量守恆
    r1 = consolidate_inventory(list(inv), max_stack=1)
    assert len(r1) == 3, r1
    assert layout(r1) == [("ore", 19), ("ore", 1), ("ore", 1)], r1
    assert total(r1) == 21


@case
def test_max_stack_one_exact_fit():
    inv = [{"id": "ore", "count": 1, "stackable": True},
           {"id": "ore", "count": 1, "stackable": True},
           {"id": "ore", "count": 1, "stackable": True}]
    r = consolidate_inventory(inv, max_stack=1)
    assert layout(r) == [("ore", 1), ("ore", 1), ("ore", 1)], r


@case
def test_oversized_single_slot_splits():
    inv = [{"id": "ore", "count": 150, "stackable": True}, None, None]
    r = consolidate_inventory(inv)
    assert layout(r) == [("ore", 99), ("ore", 51), None], r
    assert total(r) == 150


@case
def test_oversized_split_never_touches_equipment():
    # 折疊只能併入同 id 的可堆疊格，絕不能把溢出數量灌到裝備上
    inv = [{"id": "ore", "count": 150, "stackable": True},
           {"id": "iron_sword", "count": 1, "stackable": False, "durability": 85}]
    r = consolidate_inventory(inv)
    assert len(r) == 2, r
    assert layout(r) == [("ore", 150), ("iron_sword", 1, 85)], r
    assert total(r) == 151

    inv2 = [{"id": "iron_sword", "count": 1, "stackable": False, "durability": 85},
            {"id": "ore", "count": 150, "stackable": True}]
    r2 = consolidate_inventory(inv2)
    assert layout(r2) == [("iron_sword", 1, 85), ("ore", 150)], r2


@case
def test_oversized_single_slot_keeps_length():
    # 格子數不足以容納拆分結果：長度與總量優先，尾端併回最後一格
    inv = [{"id": "ore", "count": 150, "stackable": True}]
    r = consolidate_inventory(inv)
    assert len(r) == 1, r
    assert slots(r) == [("ore", 150)], r


@case
def test_empty_and_all_none():
    assert consolidate_inventory([]) == []
    assert consolidate_inventory([None, None, None]) == [None, None, None]


@case
def test_missing_stackable_is_not_stackable():
    inv = [{"id": "quest_key", "count": 2}, {"id": "quest_key", "count": 3}]
    r = consolidate_inventory(inv)
    assert slots(r) == [("quest_key", 2, None), ("quest_key", 3, None)], r
    assert total(r) == 5


@case
def test_extra_fields_preserved():
    inv = [{"id": "ore", "count": 5, "stackable": True, "grade": "rare"},
           {"id": "ore", "count": 5, "stackable": True, "grade": "rare"}]
    r = consolidate_inventory(inv)
    assert r[0] == {"id": "ore", "count": 10, "stackable": True, "grade": "rare"}, r
    assert r[1] is None


@case
def test_input_not_mutated():
    a = {"id": "ore", "count": 70, "stackable": True}
    b = {"id": "ore", "count": 50, "stackable": True}
    inv = [a, b, None]
    r = consolidate_inventory(inv)
    assert inv == [a, b, None]
    assert a == {"id": "ore", "count": 70, "stackable": True}
    assert b == {"id": "ore", "count": 50, "stackable": True}
    assert r[0] is not a and r[1] is not b


@case
def test_invalid_inputs_raise():
    for bad in (0, -1):
        try:
            consolidate_inventory([], max_stack=bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"max_stack={bad} 應拋 ValueError")

    bad_items = [
        ("string slot", ["potion"]),
        ("float count", [{"id": "a", "count": 1.5, "stackable": True}]),
        ("bool count", [{"id": "a", "count": True, "stackable": True}]),
        ("missing id", [{"count": 1, "stackable": True}]),
        ("negative count", [{"id": "a", "count": -3, "stackable": True}]),
    ]
    for name, inv in bad_items:
        try:
            consolidate_inventory(inv)
        except (TypeError, ValueError):
            pass
        else:
            raise AssertionError(f"{name} 應拋 TypeError/ValueError")


@case
def test_random_property():
    import random

    rng = random.Random(20260926)
    ids = ["ore", "potion_hp", "sword", "gem"]
    for _ in range(2000):
        n = rng.randint(0, 12)
        inv = []
        for _ in range(n):
            if rng.random() < 0.25:
                inv.append(None)
                continue
            iid = rng.choice(ids)
            if iid == "sword":
                inv.append({"id": iid, "count": 1, "stackable": False,
                            "durability": rng.randint(0, 100)})
            else:
                inv.append({"id": iid, "count": rng.randint(0, 150), "stackable": True})

        before_total = total(inv)
        before_swords = sum(1 for i in inv if i is not None and i["id"] == "sword")
        # 來源視角：每個可堆疊 id 的 (總量, 佔用格數) 與裝備數
        src: dict[str, list[int]] = {}
        equip = 0
        for i in inv:
            if i is None:
                continue
            if not i.get("stackable", False):
                equip += 1
                continue
            entry = src.setdefault(i["id"], [0, 0])
            entry[0] += i["count"]
            entry[1] += 1

        r = consolidate_inventory(inv)

        # 1. 總長度不變
        assert len(r) == n, (n, r)
        # 2. 總量守恆
        assert total(r) == before_total, (inv, r)
        # 3. 裝備（不可堆疊）格數與內容完全不變
        assert sum(1 for i in r if i is not None and i["id"] == "sword") == before_swords
        # 4. 空格只集中在尾端
        seen_none = False
        for i in r:
            if i is None:
                seen_none = True
            else:
                assert not seen_none, ("空格必須集中在最後", inv, r)
        # 5. 物品格數 == 最小需求格數（裝不下時才退讓為塞滿整個背包）
        packed = [i for i in r if i is not None]
        need = sum(-(-t // 99) for t, _ in src.values()) + equip
        assert len(packed) == min(need, n), ("格數應為最小需求", inv, r)
        # 6. 每個 id 的總量守恆；背包裝得下時必須是「正規形」：
        #    不超載且至多一格未滿 -> 證明沒有可再合併的餘裕
        out: dict[str, list[int]] = {}
        for i in packed:
            if i.get("stackable", False):
                out.setdefault(i["id"], []).append(i["count"])
        for iid, (src_total, _) in src.items():
            counts = out.get(iid, [])
            assert sum(counts) == src_total, ("每個 id 的總量必須守恆", iid, inv, r)
        if need <= n:
            for iid, counts in out.items():
                assert all(c <= 99 for c in counts), ("不該超載", iid, inv, r)
                assert len([c for c in counts if c != 99]) <= 1, \
                    ("仍有兩格以上未滿，整理不夠徹底", iid, inv, r)


def main() -> int:
    demo = [
        None,
        {"id": "potion_hp", "count": 70, "stackable": True},
        {"id": "potion_hp", "count": 50, "stackable": True},
        {"id": "iron_sword", "count": 1, "stackable": False, "durability": 85},
        {"id": "iron_sword", "count": 1, "stackable": False, "durability": 100},
        None,
    ]
    print("整理前:")
    for i, item in enumerate(demo):
        print(f"  [{i}] {item}")
    print("整理後:")
    for i, item in enumerate(consolidate_inventory(demo)):
        print(f"  [{i}] {item}")

    failed = 0
    for fn in _CASES:
        try:
            fn()
        except AssertionError as exc:
            failed += 1
            print(f"FAIL  {fn.__name__}\n      {exc}")
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print(f"ERROR {fn.__name__}\n      {type(exc).__name__}: {exc}")
        else:
            print(f"ok    {fn.__name__}")
    print(f"\n{len(_CASES) - failed}/{len(_CASES)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
