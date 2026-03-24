"""
Pydantic v2 schemas for the clan system.
"""
from __future__ import annotations

import enum
from datetime import datetime
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, model_validator


# ── Input schemas ─────────────────────────────────────────────────────────────

class ClanCreateIn(BaseModel):
    name:             str               = Field(..., min_length=3, max_length=64)
    description:      str               = ""
    country_code:     str               = Field(..., min_length=2, max_length=4)
    region_name:      str               = ""
    city_name:        str               = ""
    district_name:    str               = ""
    language:         str               = "en"
    clan_type:        str               = "local"
    clan_mode:        str               = "mixed"
    offline_friendly: bool              = False
    recruitment_mode: str               = "by_application"


class ClanUpdateIn(BaseModel):
    description:      Optional[str]     = None
    region_name:      Optional[str]     = None
    city_name:        Optional[str]     = None
    district_name:    Optional[str]     = None
    language:         Optional[str]     = None
    clan_mode:        Optional[str]     = None
    offline_friendly: Optional[bool]    = None
    recruitment_mode: Optional[str]     = None
    member_limit:     Optional[int]     = Field(None, ge=5, le=200)


class ClanSearchParams(BaseModel):
    country_code:      Optional[str]    = None
    region_name:       Optional[str]    = None
    city_name:         Optional[str]    = None
    clan_type:         Optional[str]    = None
    clan_mode:         Optional[str]    = None
    offline_friendly:  Optional[bool]   = None
    recruitment_mode:  Optional[str]    = None
    min_level:         Optional[int]    = None
    max_level:         Optional[int]    = None
    limit:             int              = 20
    offset:            int              = 0


class ApplicationIn(BaseModel):
    message:           str              = ""
    city_name:         str              = ""
    playstyle:         str              = ""
    availability_text: str              = ""


class ApplicationDecisionIn(BaseModel):
    decision_note: str = ""


class RoleUpdateIn(BaseModel):
    role: str


class NicknameUpdateIn(BaseModel):
    nickname: str = Field(..., max_length=64)


class PermissionsUpdateIn(BaseModel):
    can_manage_members:    Optional[bool] = None
    can_manage_storage:    Optional[bool] = None
    can_withdraw_storage:  Optional[bool] = None
    can_craft_storage:     Optional[bool] = None
    can_manage_chat:       Optional[bool] = None
    can_manage_events:     Optional[bool] = None
    can_manage_recruitment: Optional[bool] = None


class StorageDepositIn(BaseModel):
    item_type: str
    item_id:   int
    quantity:  int = Field(..., ge=1)
    note:      str = ""


class StorageWithdrawIn(BaseModel):
    item_type: str
    item_id:   int
    quantity:  int = Field(..., ge=1)
    note:      str = ""


class MeetupCreateIn(BaseModel):
    title:        str  = Field(..., min_length=3, max_length=128)
    description:  str  = ""
    city_name:    str  = ""
    scheduled_at: Optional[datetime] = None


class QRCheckInIn(BaseModel):
    qr_token: str


class TransferLeadershipIn(BaseModel):
    new_leader_user_id: int


# ── Output schemas ────────────────────────────────────────────────────────────

class ClanOut(BaseModel):
    id:                int
    name:              str
    slug:              str
    description:       str
    emblem_path:       Optional[str]
    country_code:      str
    region_name:       str
    city_name:         str
    district_name:     str
    language:          str
    clan_type:         str
    clan_mode:         str
    offline_friendly:  bool
    recruitment_mode:  str
    level:             int
    experience:        int
    reputation:        int
    treasury_currency: float
    member_limit:      int
    owner_id:          Optional[int]
    created_at:        datetime
    member_count:      int             = 0

    model_config = {"from_attributes": True}


class ClanMemberOut(BaseModel):
    id:                     int
    clan_id:                int
    user_id:                int
    role:                   str
    nickname:               Optional[str]
    trust_level:            int
    trust_points:           int
    contribution_score:     int
    can_manage_members:     bool
    can_manage_storage:     bool
    can_withdraw_storage:   bool
    can_craft_storage:      bool
    can_manage_chat:        bool
    can_manage_events:      bool
    can_manage_recruitment: bool
    joined_at:              datetime
    last_active_at:         datetime

    model_config = {"from_attributes": True}


class ApplicationOut(BaseModel):
    id:                int
    clan_id:           int
    user_id:           int
    message:           str
    city_name:         str
    playstyle:         str
    availability_text: str
    status:            str
    reviewed_by:       Optional[int]
    reviewed_at:       Optional[datetime]
    decision_note:     str
    created_at:        datetime

    model_config = {"from_attributes": True}


class StorageItemOut(BaseModel):
    id:                int
    item_type:         str
    item_id:           int
    quantity:          int
    reserved_quantity: int

    model_config = {"from_attributes": True}


class StorageTransactionOut(BaseModel):
    id:            int
    actor_user_id: Optional[int]
    action_type:   str
    item_type:     str
    item_id:       int
    quantity:      int
    note:          str
    created_at:    datetime

    model_config = {"from_attributes": True}


class MeetupOut(BaseModel):
    id:            int
    clan_id:       int
    title:         str
    description:   str
    city_name:     str
    scheduled_at:  Optional[datetime]
    status:        str
    created_at:    datetime
    participant_count: int = 0

    model_config = {"from_attributes": True}


class RaidTicketOut(BaseModel):
    id:           int
    owner_type:   str
    ticket_type:  str
    boss_tier:    int
    tradable:     bool
    created_at:   datetime
    expires_at:   Optional[datetime]

    model_config = {"from_attributes": True}


class ActivityLogOut(BaseModel):
    id:            int
    actor_user_id: Optional[int]
    action_type:   str
    payload_json:  Dict[str, Any]
    created_at:    datetime

    model_config = {"from_attributes": True}
