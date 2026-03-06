local DUI = unpack(DDingUI_Profile)
local D = DUI:GetModule("Data")

------------------------------------------------------------------------
-- 전문화별 고급 재사용 대기시간 관리자 (Cooldown Manager) 데이터
-- specID를 키로 사용하여 각 전문화별 CDM 가져오기 문자열 저장
-- 포맷: "1|Base64..." (블리자드 CDM 가져오기 형식)
------------------------------------------------------------------------

D.specProfiles = {
    -- ============================================================
    -- 전사 (Warrior)
    -- ============================================================
    -- 무기 (Arms) - specID 71
    [71] = "1|PdC/SgNBEAbwS5A0NhaC+51n0PgEIhYyV1hsGluJrxCiogbEykgurNEXEKMJkosp8gA2iuKfUlQU0wj6DHaW4nxXXPPbYZeZnRk3Uo9H41yjZc2kCRBW4e4hW5BT2IHvZXa/jA+5hLuD1CFqA9IxeX2aq5K2Epcg55AzyAlulmDHIS1IG+4R8qbve8uQd4TbCLXwB2TIxA4Tj+Ee9Kx949roWfZJEgWkQKBEE7j6ZdYPb6bIDJlVnrvKS1F5tYya5JAcKQuLZI2skw387bOlW35bIRdKb4XVONX8mPL51PcOdAG6Bt/Lru6YvA6dbaYNBGmbSLsuTEfJKjJRMl2cK1pb2Sz/Aw==",

    -- 분노 (Fury) - specID 72
    [72] = "1|NdC7SgNBGAXgKAta+AJHUFIpijHqblS8ROWYWqx9gH0CW7OEnWiCl8JGrHYN3oKdoCIJCGoXEOwsRLRNwCIv4JxImm9mmJl//jOhE8QDsVM4yYGH4D54MJjoqRRhhsA0zDLMMHgMToEzWC+CLpgBPXAOXAHnwVmwDZO196afxYt4Ra0KHoGLdrXzBC6Ba3jfBnWwsov6qR3zWxavhMcv5FbtNIhQ/7Gje6/NhsWfEAtiRIwK1fRTIi3GxLjl7VxciKq4FFfiWkW/UfvVe7fi05Lp05uTwldXe6Ikytrtt3xsniXKimyynaRuN7in7PqQdq/pdhxEnY7/M+QbsbPRisJW4SaZSjbvwqZ5+AM=",

    -- 방어 (Protection) - specID 73
    [73] = "1|NZC9TgJRFISXhSigqMFomJXlR/QJiPSamEwjRHsLbbTS0tbNou4jaEliYWOznaG3Nlb4Am6obUy08Mw1NN89c+7NZOYOC9ejShTf74EbYB0MwQJYAgOwA+bBZXAFnAPb4CLYBDeRTsEiWEH6BM6D5cDLPXrgAljF+BtcAgGu4v0TrIFr4Lo9Od0Ft+zs9fH7guzHxo+S4ewIWaD9ANwOPD98NjGp62agqSmEkoeGt1gYColwI9wKd4adLzNodDU9CK/ybQkHCunLSnLSkN8xxh2tLX3imhRd+bLr7+qlUz9xEWdhe/3/pFlgDSyvVWpFVr0dO6OZ68i+Kopz+Rqi/YuTy6vzPw==",

    -- ============================================================
    -- 성기사 (Paladin)
    -- ============================================================
    -- 신성 (Holy) - specID 65
    [65] = "1|Pc/LCkFhFAVgdF7BYHkIM49giMgLmMmAWpSp3IlSriM67hTSeQtvYGBgYHp4AWXvP53J1+6vvfb661bFDtpWdRYGY2A85PNn6koDTIBJcAWmwDm4ADfgEnyBa/AL7uA64AHcgntZetx0s6O0la7SUprgEW4ETMMd4v1E6arPA7zloahjXzg9hfNHuAyFe03I6ZQbKRNlrMyU6dLX0w48mNPS6N9bGu9NxY35jdZznUDLCzMRU3PfizWJI9uK5jOFcvYH",

    -- 보호 (Protection) - specID 66
    [66] = "1|Nc89TgJRAMTxhUiltiazFYulmMwVbIygCYgX0EYTW/OWLwVcNgEsMHRUygNLC43GkFhyDVspFAtv4JsQm181xfzjlZbdsKlouANTganC1DBbA6/Btu8lVi/ACIzBDmgQroN9cABeglXwCqyANbCl7abYBxtgEyyDdTDE7B28hakj3EL5F7zBPAC7bnu8K/ZETuTFgSiIojgUJXHkOJ+IO3EvHsRIWDH2vSTOHH5GnDiCrDgVI2GFdsGHI1MQRbCHz7ex11Ojovr/XcvMgQtPtt3p5XubKi3i56/p0yJ6TG+nv19ef4bTPw==",

    -- 징벌 (Retribution) - specID 70
    [70] = "1|a2FpWCi+kLlphrUUA6NXIJDwr5X0PijpvVfS+6ik9wlJ7yuS3uclvfdLep+V9D4g6X1J0vuypPdFybBHkmFPJcMeS4aXS4aHSYZHSIaXSYZHSno/lvS+IBkeLrnlHtCwjWeBRNZqSe+dQHq1JJDwaQQSG8SAxKoZIOIdkFjDLOm9A6T6NEjBKpDwYSCxrh9EWAGJKqDduyVP1wGZ3CCZjWeABI8pyOylIGI5iFgBIlaCiGVSDEwupSB7HEGmTwQS61NA2s4BCT4zEOvUYoYWmGeA3rvC1A0zG2LEUqg5SGZvPAPxBo8pxDGKjWDTFjK7urhk5qUDAA==",

    -- ============================================================
    -- 사냥꾼 (Hunter)
    -- ============================================================
    -- 야수 (Beast Mastery) - specID 253
    [253] = "1|PZC5SkNREIaz+AziHxhyU9gY7hMIGpdsjRZyBQUbJU0upBAVC0ENBiHJTWKX9jY2LiB2blkgnfoONmqpCVg7/zGx+ThnzjDnm/9k7MifiPnhYjMVCYQSB5FAMDkFmYekMHC0tDUOyUIykAQGh4jeake+rA+bGbgduF3IDNwPtHqQdcgaZEM7Ck30bcgsJA1ZhMxBFljeQ9+B24Z86a36SrxwYJXwMDlNiSe9pN74hSk3iDqifUS/qRcnbEX5mi81dpvTmWL/jrgnHlir8PRItIkO0SXeiU9OuSAuiSviRlH5oVmOeFZ4WTa3aOSdB49NAqHKyJuqQxdvqPa3Q75u9NV8tEsyHiuNhprFGYEONabh4v8mNavETE1QzLfVC5yaNJkjA2W4ac3SDy8vOVnLtjK7hZ3ctrWy+gs=",

    -- 사격 (Marksmanship) - specID 254
    [254] = "1|a2FpWCih0PStaYaDJMcmSY7Nkj1akpzikpwLJTnuSHKxS/LWSnIukuQSl+StkeTikJTdJ5lxRJK3X5L3oCTnYsnPJyQ/n5RiYHTZLLm/RvLzKUneHEkuTqBAVjuQcK2V5LMB0dWSfCIgwSYgUZEOUr8VRGwDEp0rQBKNIFU1IFYHiGgGES0gohVEtIG0pYKINEk+BhA9GURMlewBC04DEdNBxAwQ8RRk6lIQsUySLwBELwcRK0HEKiDRVQgkunuARI82kOgFufSHE0jnFCkGJo37SxlaYV6uBYUDFztTJ9zd22DeAPsA7G6wV8HecK0Fe1axBerKKUD7gW5UaAQGDjNYaXPTN3+/UE8FXQWP0ryS1CIFX18A",

    -- 생존 (Survival) - specID 255
    -- [NOTE] 실제 생존 전문화용 CDM 데이터로 교체 필요 (현재 야수(253) 데이터 복사본)
    [255] = "1|PZC5SkNREIaz+AziHxhyU9gY7hMIGpdsjRZyBQUbJU0upBAVC0ENBiHJTWKX9jY2LiB2blkgnfoONmqpCVg7/zGx+ThnzjDnm/9k7MifiPnhYjMVCYQSB5FAMDkFmYekMHC0tDUOyUIykAQGh4jeake+rA+bGbgduF3IDNwPtHqQdcgaZEM7Ck30bcgsJA1ZhMxBFljeQ9+B24Z86a36SrxwYJXwMDlNiSe9pN74hSk3iDqifUS/qRcnbEX5mi81dpvTmWL/jrgnHlir8PRItIkO0SXeiU9OuSAuiSviRlH5oVmOeFZ4WTa3aOSdB49NAqHKyJuqQxdvqPa3Q75u9NV8tEsyHiuNhprFGYEONabh4v8mNavETE1QzLfVC5yaNJkjA2W4ac3SDy8vOVnLtjK7hZ3ctrWy+gs=",

    -- ============================================================
    -- 도적 (Rogue)
    -- ============================================================
    -- 암살 (Assassination) - specID 259
    [259] = "1|PZFLSwJRFMe17BsUeGwztssS2vSAoDTbtHERSC0boQmzdDEVdyKwBk0nCAJBLIPMRwntsictal32+CC5S1cFnf+YbX5nzr1z7zn3d+K27VN7v97UswEy5kjsOSzWTJ20IRI50sYp2UdpJ4kNElskQiRUaoyQNkYiQ9owiX0SBzhhA4IkEhzlb9IGkH+S0KnxRSJNIoaFTqCLEZ4EvICHcdzDqFwDV4zlKjZ8tKkguhm5IPCAX7sZFwWgCJSAMnDGUGr4OifNzzGPJpRnxpGLjCxp07huCgVQ5fAHeAXegHfgg1F4ZCyskFjlWHSgqyqVJnB4FMkNGfeIt8AdgLRQR7UXpHEAJiqX2HjCNb2ME1TMu4DBsnXHNN2R+n+wty3BtGOaCPvadsIeyy4GwNJhH955BlLqz3sMqkWiZbs9A2fS9MceWx0rNX4Gu2EZenPe7g/MSG5pNrq0vih5VVVW5Yi8FopGfgE=",

    -- 무법 (Outlaw) - specID 260
    [260] = "1|PZG7SgNhEIWjsdAXUI/VWtgI2cbSexlQAyFJpZAgarGCFrkXKqJYiMX+pBC0yCabmE0qESOoCMEnsBC8pxJsrC3SOGcTbb6dHYbh/87s9exYg6OWd/c4MOTpupwQ1C2oAHyPcE7ZmoLKwLyH+QC1BHUONcuhPCpF6CGoEehhlHxw/FADMJtQfTC/YbagDCiZmYM+D7sI+wt6BGoM1XFZ0KgJruMCw0WSSBBp1LzQoyj/8C8DPcbxiiD6KbgNCVYX2TuDHkSxn2MpgfPOKiu4emGVY++VeEPhmd8PCk0ie8E9Yc5sE1tcZhNlooRCDLUTKW96ORhh0yGqgrsnLpkhGMTmMqtp23NAcUlAAqF+k/pmq/vw3zDt6rjv/tMwkh3LRNvSFWxUtCNGJhdo5+XeoZ7vHCPAe7TjdNMd3m/LuYEaOclDnm95gwthv+bTghtriRUtkIivx1K/",

    -- 잠행 (Subtlety) - specID 261
    [261] = "1|VZC9S8NQFEfTKo6Ktk3yi1Xi1KF0dtB/oAgifoCjCEUogqDtoHcxRYgZ0jw6abcOzeTuWgW/qp1EHDK46eAiLk6C96ZScTn3wYP3zrlHw4ctM+/UTuYsLbHxioMn0CTIAgE0Bcqi8QxKwdPhZ0Hj8Ivw3+B9gExQGqSDMnC/QYalJUd30X5HOI/jJTx+od1EkEN9HTTBr5c7UGWZl4J7QRehJ/NWcCF4EPRwNivzSnAtuBPcgKZRz/M/mU+oCErxcWyEkToVaHJTQBDx1M8ZxoLghWHuhZoba6YlgpVF3OCIpDew6QwEuv+lerE1VwzV/mQSDi/Ldn874+z+Brg9yM24fdm4JPZVohxEzuriWtEu2Ms7W9WSvVLdrGyXKvs/",

    -- ============================================================
    -- 사제 (Priest)
    -- ============================================================
    -- 수양 (Discipline) - specID 256
    [256] = "1|LdC7TgJBGAXgZbLFBDeZFRsOlaHwCt4TsdDEgpj4FnZWLo0xsRKzruJdCqTd+AYKovgAVrzB2noJnS8A/5nQfDOZ3f9k5oTuSZxdjd3TZhn6DboD7xj6FfoDug3dzTlqax36Hd4OvvJIBhjrIOli/BPJIXQr56SKKzA/MH1kImSmZGD3l6fLMFwLVXgTMN8wf0gHSNZ4dk5q5JJckWtyQ27JHbknD6ROGuSR4TNklsyReVIgRbJAFsmSEMiEmvwXSj0GnMluw+cu5C/T3F3AT3ON4Eu02nwmL0ReqLaVfKtkn1JV+yBlrx/ZOZtghyR4FBI6NenCNmPbkFbYkDRo+qM+27FbPtgLjvaH",

    -- 신성 (Holy) - specID 257
    [257] = "1|a2FpWChh0vStaYaNJJeWJJe2JJeGJAePJAeXJAevJAeHJAenJK+ZJAerJAebpMFeSV5bSV4rSYN9khzcUgxM3iqSvHaSfEskeS2lGBhXzgcK2W0CsRZI8ppL8i2V5LWWFDovKXJKUpxBUtxestgJKKlyDET8ABJqkUBCVQtE9AEJ9RCQhBFIQh0k9hXE+gCSUAIRbSBiB5DQkAURciAiAEQEggiQbPJtINHOAiJeg1yxEEQsAhGLQcQSILG6FEisMQURh4HEuoOLmDphtqr8gDgQ7A5VLaCDYW4EO1m1j6EN5Hmgj4GhwLcE6n/Lpm+OeQA=",

    -- 암흑 (Shadow) - specID 258
    [258] = "1|XdC7TgJhEAXg3YWogDGx85D8YRI1saD0tomE0MhdvKC2mkhjga2FJoYsLI0VBRYY2RjAjoJCCx/Ah7D0AWysdQ6lzZe/mJOZ/3jhu2BpIwg1HioQB2cdJKuQGGQeEobMIPGLvguxcQ2YLcgcJBK3bH9VGXkwm5BZGBdmHSaF5SjMDsw2ZIFDVeXxltxg7RS1DJIfuLhndI9UlMsaJ3dJluRInhRIkZRImTDmM+bvkwNySI7IMTkhXfKmPPWUQZSMyKcyXCRcORyTL96CuOWkLb6apEV80ibv5Ft5WVHGrjKxCU+blHH+qvFUnVwpuR+lEHu2PJam1UlEq3O8//+XxrScaU1BKFP/Aw==",

    -- ============================================================
    -- 죽음의기사 (Death Knight)
    -- ============================================================
    -- 혈기 (Blood) - specID 250
    [250] = "1|LdC9SgNREAXgNW7lJqa7eNLcyNj5CqYQH0CwkS1T2milEisVRQikFGwXjJDHkFSKJP7kEWLhJtFkNQpWzpnYfLvcO8zMPWfhcbJUScLTqzX4F/hn+CfE83Bj3DcRh7gbwz/CfcB34HulILcRw3chRbg3uBRuBKnADSERpADJQxbRvkR/tRTM7Rwp1ZQMyYhk5J18kgn5IlPyTX7Ir9Jn8euFkjZIBtnUHRYeWDDQv6jFlTqQW46rkUNyQPYhN2hvQZpaVNjDitPTwTapXy+f23d2aKvYTTXL1a2lTfjvay1rNnvW1UZo6/KJphY0GBEfH+mzGZRGoAFpCr7HRDQd37XoknB99w8=",

    -- 냉기 (Frost) - specID 251
    [251] = "1|RdBNLwNRFAbg6aRDqj+At+mC2HdDoiuJqBWJtv4DmZxBwoJYaSpCbDRBh0RrROJXEAuhv8DOVuor8dEISuK8V4dk8szHnXvOfc9KdDnoGgycoj8Erw3yjukBeO2QOuQWcgd5gNxDHiHPmNXrBbU05BvShDQgT5AvyAduhiGfkFd4Ni6aCSuSnVB2+pVcTBmvK24Fl2/wHC4vKvkO0scfT5XtY2V1k5woW+f8NqaURxW/RM64N8WqeS4skSS54ior++yZjcOz4EX1cfeAnQNSJeZ1X9mbJNestaBU5sh8wrJ7O4+stf+8zNhoRa6l7fVwv1v962GKmsS52G98N+gu6BB7NsJDm/OaRuVkawTxMHM2pXMJp+CXDk2xQtF2IlrM3ANnJJNxZ6Z+AA==",

    -- 부정 (Unholy) - specID 252
    [252] = "1|TZC9SgNREIV310UFXQ0SY05A/Ol8ChFErNNoYWMVYnZ2CyF1XEUQC6OJiaAiFr6BWGiaYOMTWFjYJRARxCYghuicGyI238zdvffMnLPnFq6Ti1E7OluGTEGSkDWIi6ca/C7ESll2JoHwVuvWG8IQMgoZgIxBhiAx/RzPQBz4HcgIZBzBO2QY4vFPFjKIRlHb4w3IJDU+IBOs38QnL+WIgPAJIUqK7EPKcuafeSxTYZpdVbH5xeM58aI4AbFOXClK28S9onxKlRqfsYtXVG8hr93Fo+LyR+HVFUcNRboFSWidWaFQk89XCVtRfOWFuxt7x5hy9o1kz1BPv2IsqTXrQLMyGWlAMZOUxuT205vdZUrMypk7/Btk95cwHtMtM+3fOma+WcerR+2l4Bc=",

    -- ============================================================
    -- 주술사 (Shaman)
    -- ============================================================
    -- 정기 (Elemental) - specID 262
    [262] = "1|PZHNLkNRFIX7c9GWGlFdTSQkEgnx1+yTtoikCapRambQMiHBREo8AFpSBA0Gpndg6BX8JDcGPAMvQnHWaXon397n5OyVdfaqWId2NGNbx/drkDRkFpKCOoMsQ+YgM5BpyAIkB8lDsih8QiahziHzMY/X8UNOIKdQd5AVSAWqBnUJdQV1A3ULdQEpQ1WhriFLkAyHLI3EDwpfkClIkqc6NnZYf4k/rPfqmvTGPL6hb3Y+ooVoJdqIAIqbum6/EK+86SS6iG6iB8V21ijxTnxopEaIUWKMGCcmNA5W2Q1S7YmPI+ye2QWJEOEnjGgHUSL2iH3ODhBxHsPUe+Rf6dehXydAUMqhlEMVhypvW5BFTg4/eI/Meny1ppOGeKQpnqi7JoKuk7Drs+Q6ibu/MD5DnqoJNG+izJp8c40Q+8qNEHQa/RWzb701vVkdgW2ld/8B",

    -- 고양 (Enhancement) - specID 263
    [263] = "1|PdG9LwNhHAfwag0GJK008TUxmZxUE4leenpn6VBv8bKjAxGvCzbR2o3WS/wDEm1p0RateAmDtgwl9c5qMVg836dq+dzvuXvunu/9fuHqVbPRb9rWNiegTEKZg2sFygLUeniCUBbhzqDDCX0dHjtcRRgq9BI+HfBG0L3TZKnSB+CLQOtj2Q+tHd4vloPw+OFbghqAJm8MQW2DNsNS7g2QXnR9w7vM8p0k4J7mtYBWuWmfHJCkIH7FKkWOyQnJ8ME1Oue5OBVMjZBRLi9JjuTJLbkjRVIij+SJPJMX8kreyIfA2CV7JE4Yx2AI44gwhBHj5jQ5I1lBMsrqnFmGYXNyF//BYPKYyWcXgnCtIDEuOOwRpH4EN2OCXA3ZFuQdgoY6WGUbH8j9liUsJ2SXgwlaN2QHy8eUP16QB/+/ka6cLwPKEMnoX7MTlTAyrZ5tDsnRyCGJibWEKq2XbTZt+uwv",

    -- 복원 (Restoration) - specID 264
    [264] = "1|RdDLSwJRFAZwlbaB2gO/6aX0sCAntQc9jGhR0R8Q1SYoa+HGRXDWMyO6KYue0C5ctGpdaIFEy2rVfxKVUqvONyJtfvec4d4793z5FrsUWnVyV1uGx/tUgvUD6xfWF6QXVg3WN6w6ZBDSD2mHRCDdkGFIGNYtpA8yAunRo9VrxazArsOuQYKQGMQPGYIYkA5IG6QTEoAA0gUJQaKw3w2PL/bGk7p7g+usklgmK2xTsPfgvMIpsBtXMmlWM0r8XLmrsp0nJhkjCZJU9ndZTZBJMkWmecsOnBc425B1flogZd55QA5JkRyRY3JCTskZuSCXfOcSPlr5q4By7yduFSSfSnlUqcQJ31V5VB7mIJvIrUEGtHtO3nhzboaasa/YGDaT1rndRBrJuNOasWYMbgJm6j8tT8ENO9oM2Ag7mm8k3xhSp3XjcBazfw==",

    -- ============================================================
    -- 마법사 (Mage)
    -- ============================================================
    -- 비전 (Arcane) - specID 62
    [62] = "1|a2FpWCgR2Nj0bRHTDGkpBkarWZIX/ID0zpdAIuk8kLDcBSS2xIAIXSCxaTuQ2FwDJE49BcnuBnHXgGT1QKxakN7nQKJtv6R0IUikGkjYsQMJa3kQtwpE1IFUvQCpOgDSGQ2yWAQkUc8wSVLMRvL8LUkxO0kxI0kxJ8kLDJJixpJiJpJiZpJiDpKP4iTFTCXFLCUfdUiKmUuKWUmKOUuKWTc65gEA",

    -- 화염 (Fire) - specID 63
    [63] = "1|Fcw7DgFxGARwrNprPHZWnERI1ise2Yg9ggoFcQMR0ehUoltXICg0JAoqB9BwCLX/NL/km5l8i+gssP3Amv92kU3BCYUvCZE2lLaG8sewvIq7iqTICBpGUxU3Q/GkLCZSImvo37kaqjuIs+K4gMiJvH5MSE+HLRxNj2IfWhNtokN0+X0TLtEjKoRPeESTqPL14OtJ1DlwiBrRIFqB5Y7/",

    -- 냉기 (Frost) - specID 64
    [64] = "1|Hcu7DsFgHAXwki6272sMjtRsd1saCU9A4iEkBqNZGvEGEquOGMyUoi1zn4Jo3ZbOvmP55fwvZ6KPF4Wendqpo80gvpBdyAqiEmQN/SbyOcg6DA+yAcOBiBGZEE+IF8QbUodIID6QHchqdm4WtUxrqZhGCndLzuRCdsQjPrkqwpXCupGYuxO7vFoPjiHTnelIArJnbc3kKgYjviSKYMPu/+Wg8Mt22h7+AA==",

    -- ============================================================
    -- 흑마법사 (Warlock)
    -- ============================================================
    -- 고통 (Affliction) - specID 265
    [265] = "1|Nc+5SgNhFIbhMQTFXEHeFJLCVrwDl/IrLSzFpRAJLolxXyeTqFOksRBsLGKhIKkkd2Ehgt6ESSphYqPxnIDNA/9ylq+WDhvZhUp0O5MLhlIXqEn8TvzBdxZtoRCtoTN0jE7RCVGPpEpvDO2gItpE5VyQyiw5i+gQHdDroCO0j/bQNiqhXZInkjdUQ5foCsWs2us62kCRTS9MOdOGzp3Qqfid7/bzYPx+Gf05p2/zgsC/eK2qdky/GMMlp2GMjBujs86r4xWZSWfZWUGF+8ASlwdRLEdxkCP13886V+a7d9ftx7j9fNOJmvmJfLde/2y1/gA=",

    -- 악마 (Demonology) - specID 266
    [266] = "1|a2FpWCgRs5C5aYa5JPtuKQYmtyZJXiVJpvmSXNuAPMGtkpyVkpwXJDmTJDnOSTLzSXI/leRilPzuLMl5UZJzvSSnniQnkyTnbMnvTkDlApkgIkvyu6vkdxfJ745AHv8EyY51kh3rJVUZJFUuSapclBQ7KykmKsn0Q4qB0ZMBSHhcAxHXQcQVIJFlAyJsQVr3gUzLBhE5ILckgYhkEJECJESAepn09kky/QaJbJNUiAXSwumS35dLim2UZOZcytgGdAHYHa5gV4EdA3YkUwvCWphDGNpBfuRihHga4leQvysVmiAeUGwEWrGQ2TEPAA==",

    -- 파괴 (Destruction) - specID 267
    -- [NOTE] 실제 파괴 전문화용 CDM 데이터로 교체 필요 (현재 고통(265) 데이터 복사본)
    [267] = "1|Nc+5SgNhFIbhMQTFXEHeFJLCVrwDl/IrLSzFpRAJLolxXyeTqFOksRBsLGKhIKkkd2Ehgt6ESSphYqPxnIDNA/9ylq+WDhvZhUp0O5MLhlIXqEn8TvzBdxZtoRCtoTN0jE7RCVGPpEpvDO2gItpE5VyQyiw5i+gQHdDroCO0j/bQNiqhXZInkjdUQ5foCsWs2us62kCRTS9MOdOGzp3Qqfid7/bzYPx+Gf05p2/zgsC/eK2qdky/GMMlp2GMjBujs86r4xWZSWfZWUGF+8ASlwdRLEdxkCP13886V+a7d9ftx7j9fNOJmvmJfLde/2y1/gA=",

    -- ============================================================
    -- 수도사 (Monk)
    -- ============================================================
    -- 양조 (Brewmaster) - specID 268
    [268] = "1|LdC7SgNBFAbgdTeSvIH+gZAEhXPUQvANfADfQLBR8Bq7qVWitdhou9jaWPgSihfQxBjxOtYiaLJmEy/nF5vvH04x85+pZtbiwbk42dibgluBW4ZbgqvA7UC6cKvwE5DvfNBXfIX8QLvQABpCI8gnJIGk8Fn4HI524euQL/hrSA/SgrQhHfhp+Ab8FnwT2g/NQVsYKeSDsLAIzdrVpbIxvw3tQBNoGy8Z6IfNZk7IKUbfMDbO4xk5h/aYF+SSXEHfmTXSIDekSW7JHbknD+SRPJFn4tllwSgeG6UBMgtNmYfG0AFJjOH6fnnTurCRptbDHg6r1vp/m/bfIsG6/V0cTVZ+AQ==",

    -- 풍운 (Windwalker) - specID 269
    -- [NOTE] 실제 풍운 전문화용 CDM 데이터로 교체 필요 (현재 운무(270)와 동일 데이터)
    [269] = "1|TY49bsJQEIT58SGYdFxgn5GSA1DQ2r4CDaAUOUMcBSkFEBA/QhQIQ0VDCIY6GCToIgqgQfxUVCk4ArsPijSf5u3um5l349WLZTzjrfkIKoBKoOJDKJz+EowF3wJfMAJ94q8F0wLVQGWZDUEVUBWmA6pjFoNpQ/VlM4FagBqgPegAOkJloVyoJdSG9/6WMTyDTgjaLAN5zx3G4YOR41nEecJlgMta3l3GT1hUB8EOiWeWoyRjmuJLe8XqV0pPor1QnlvcK/SlqmlFCuykf2i7f/cSxJ464uaqU6YpTom72tAzki9X",

    -- 운무 (Mistweaver) - specID 270
    -- [NOTE] 실제 운무 전문화용 CDM 데이터로 교체 필요 (현재 풍운(269)와 동일 데이터)
    [270] = "1|TY49bsJQEIT58SGYdFxgn5GSA1DQ2r4CDaAUOUMcBSkFEBA/QhQIQ0VDCIY6GCToIgqgQfxUVCk4ArsPijSf5u3um5l349WLZTzjrfkIKoBKoOJDKJz+EowF3wJfMAJ94q8F0wLVQGWZDUEVUBWmA6pjFoNpQ/VlM4FagBqgPegAOkJloVyoJdSG9/6WMTyDTgjaLAN5zx3G4YOR41nEecJlgMta3l3GT1hUB8EOiWeWoyRjmuJLe8XqV0pPor1QnlvcK/SlqmlFCuykf2i7f/cSxJ464uaqU6YpTom72tAzki9X",

    -- ============================================================
    -- 드루이드 (Druid)
    -- ============================================================
    -- 조화 (Balance) - specID 102
    [102] = "1|JdC5S0NBEAbwzCoBC9Mp3xfUSq08/gEVzKuUkEI0aOtVaaJiegnpgkdhIXZPq2BaCdgmjRdYe0BEC0sPPLByv2fz253ZZWZnS61bIfJhvHgwjQUsJmM2l/DM/mIJy4pC3KCKY2RRxyFfarQWWoUGPPrjlRO80XZou3inOZ+5O/M0y7RNTo7Rtml1WoO1fZ++rzCIinbQBrU2aAFdO12CbkaJTs/qiBgVWZETebEm1tX23HPb1O5KXItLcaErUaku0S16RJ9n/kk8K+wXAyJ6yJAYFr2a/odBmwptMCgr/vY8TGj3JT7EJ1N76lhl6jQZc1OvKCCNzJErIYNCNCXSseL/f4Xx8dwf",

    -- 야성 (Feral) - specID 103
    [103] = "1|NZA/LENRFMZfX899ki4WUZ/JfxKbydJBUoNVkBobg0RV2GhERATVxL/4N0lun5ikRkvLaBaJgS5SCa81WG3O98LyO9+5595z7vk2Zd22LdroxvlEuxNpPVKkHiFPTI5hEjCDME2a1YZhAFmB5HCxBFmGbEMuIXmID7F8cKjIxqhOFOkr1N81zndCChozJcgqZFfl65zibQiygzUXtzXNqtMwBZhneKfwztijTjTgxeAlVM5G2OODqoXqmq37iG6ih+hl1WH1RvFyQPVJsFemwSsPVAHVAIzPERWiDPPNeEfcs9yhmKny9hdGm5Gc5GE/klO0iD+Od/GEiKeIPWKf4NxskdAB7vgY1/th46DoboVbhfvpqmHlb9/AydNfmuuHtqq59t/onI2OLPwC",

    -- 수호 (Guardian) - specID 104
    [104] = "1|JdA7SwNREAXg9RJwcjdNwCJnSaEgmj9gYRqxccFWYzb4YFsjCFZ2oota+OhtRCSF/gqx0Cq9TYrNy2SzsU5l4ZzYfHCHmWHOvcycPxdOokn0sIngA8Gn58xkDewtJIZdhi1DEkhby+YX2TzsHW5WYO89x2w0tRrWyZE+CwOSkBFJyQ+kD8lAUsgAp4s4q0N6kA6kCxljfk3HZxMyIikZK5LX8a1VLq/CDuH6cEPkQq36c6xukwrZIQGpkV2yR/bJgXL4rrQ8HhSTNumQLumRPvkmQ6I3GJQU70spvpBXZYktpSfkHnlfxOVvDeeaMfW7GDNmXls2V9Ozw/8Erj/tXLjQwWiyfvwH",

    -- 복원 (Restoration) - specID 105
    [105] = "1|RdA9L0NRHAbw25t2667PZfmfQ2LWpiQ0NOItuI3FjGCRGHyCRqQVNpP1MjU+gMXEoBKJl1JBUu1llvgE7f+5JZbfeXvOyb3PXrwYpHaCxO7xlOfEVqswRdgDmB6YURgPBjApz3GXemEfIDnIPMSHzDLdhExAFiEzXD2Sd/JErsg1eSMv5JXckxr5IHVySz7JMwkhecg4pw3ItI6tEmQO7W+0T3HOjbUQ1oddgW1hYAuDd7q3ucwbX+SGd8r64UNJUiBHRN93s2fKcFZZiCnpPv7gOg820B/i5wJ2TFeZS2VkkonKibv/l9RQdJyudMP/SecwqifHTtiW/9tMs1sgy4p6qwaJ/HYH",

    -- ============================================================
    -- 악마사냥꾼 (Demon Hunter)
    -- ============================================================
    -- 파멸 (Havoc) - specID 577
    [577] = "1|PdG9LwNhHAfwag0GJK008TUxmZxUE4leenpn6VBv8bKjAxGvCzbR2o3WS/wDEm1p0RateAmDtgwl9c5qMVg836dq+dzvuXvunu/9fuHqVbPRb9rWNiegTEKZg2sFygLUeniCUBbhzqDDCX0dHjtcRRgq9BI+HfBG0L3TZKnSB+CLQOtj2Q+tHd4vloPw+OFbghqAJm8MQW2DNsNS7g2QXnR9w7vM8p0k4J7mtYBWuWmfHJCkIH7FKkWOyQnJ8ME1Oue5OBVMjZBRLi9JjuTJLbkjRVIij+SJPJMX8kreyIfA2CV7JE4Yx2AI44gwhBHj5jQ5I1lBMsrqnFmGYXNyF//BYPKYyWcXgnCtIDEuOOwRpH4EN2OCXA3ZFuQdgoY6WGUbH8j9liUsJ2SXgwlaN2QHy8eUP16QB/+/ka6cLwPKEMnoX7MTlTAyrZ5tDsnRyCGJibWEKq2XbTZt+uwv",

    -- 복수 (Vengeance) - specID 581
    [581] = "1|Pc9PDsFAFMfxaWvrz1Kb2Ng7hHAN0sRaUW0QGxFCJbWTiF17DEXSW5C4gL8bFzDfim4+814mM+/9ZplJUBwH2nRb0WNhCMXs6LHC6emxxjmQlEMq2xBq/Uq1hAX0oQcuONDlxY7KkrRuknUTGrR3iR/RFmif8II3F3s4wBFOcIYLfHiWhRzkoQZDGEk2JaA12xDw8yNU5/8lkvnJ6GQdPxKrJPV/8V8YO83mpKG9NLkbaFXrCw==",

    -- 포식 (Devourer) - specID 1480
    -- [NOTE] 실제 포식 전문화용 CDM 데이터로 교체 필요 (현재 임시 데이터 — 게임 내 CDM에서 내보내기 후 교체)
    [1480] = "1|PdBNDsFAGMbxaWvrY6lNbOwdQrgGaWKtKILYiBAqqZ1E7NpjKJLegsQFfG5cwPxLu/nN+2YyM+8zs9TEy489bbot6aEwhGK29FBhdfRQYx1Iij6VbQi1eqVawgK60IE+9KDNiR2VJWncJOs61GjvEjegzdE+4QVvNvZwgCOc4AwX+HAsDRnIQgWGMJJsCkBrNsHj5oevzuMhovejp6Nx3ECsotTx4L8wdpKtl2Rz/snlH3ha2foC",

    -- ============================================================
    -- 기원사 (Evoker)
    -- ============================================================
    -- 황폐 (Devastation) - specID 1467
    [1467] = "1|XZFNLwNRFIY7zeRI7DXeruiaFQsUTXxs7PwBE5uOFXZNdz5q7AS1sJ2EdOjGwoKoRIJ2WiXqB0wm/Ahb571aC5vnZu6d85w355TsLX9w17d3ThcgNcg95AZyC2lAHiBNSAfSgoSIn9MJa3MaXpFnCt4cz0liiphRtCqIluFdQd4hL5A25I1vE+jrR3SN6DudSOaOeJWFPELqOCjolzPAq0OCj42sIrwjaopmjupxIiAuiEtFe4QYJT4U9Y7i8wvyhHierhOFW1G82tTMsm6M7fKKlSX+ckyUEWcQW/Q4LKkSbOAGiM/OrW0TOGnylY2E4eNMz2xUbtCrd/K/MqMwHUwI09+tqnG49D/o0F53cF6xO9hUYl9HbvYQ/u3BbMC3F9dXNwprPw==",

    -- 보존 (Preservation) - specID 1468
    [1468] = "1|PZA9T8JgFIVbThMZJSHGwySbA6MOEiMa4+aicaJUwQipXwVxcLWEqGFwNnEwDISFTRN+ie3mysTC2gS916Ysz71578e57+laj/3Vrt952yYuiDpRI1yiQdwRfeKMwQ/Tmwzec4ZpZokb4pooEG3iitYKwzzRk2KlnTNSpV/BbpHpDaJK3BIe0SLuubTO6RennwyHRETrUEacCaNXjbaiwGhL92QV+wJvpAgFzSPFMa1LiZmZoLUjqJ5rw7ciEN29kmTlucAeC9xTHTrRzFHYXP4YmL4ckHpJKuW5PCa9zuS/LRmwx/mnRCQzi7UXYnLAWif+pvGsHogTsSVqT0988g+8WvPB/QM=",

    -- 증강 (Augmentation) - specID 1473
    [1473] = "1|Lc89S0IBGAXgq8j5C7WcBOegxaEp+gvVXkpFTTn1QUteDBxbBD+wuARNQY79gBZp78uucU3TbrdcpLn3qMsDL2c47ykmTr35Mw9uJUN/gxgSfWJAfBKPxBPxRTwT30SXeCN8oke0iYAYJZ348j3xSnSId+Ij6cSyQzGwaP1E3DJIEy/EL/2WRbk/Y3PJ2D0Qhzr3xI7YEtsKjsSxsV8RVVETDXEhLsWDGBv5ObFmpSshO4vEz1WsYO1xd3o5pcmC3mREMPvdVo1sj4fV8K4Z1c8j9ya1kIquG2Gz/A8=",
}
