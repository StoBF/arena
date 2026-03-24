"""
Seed all GameResource rows (craft materials + intermediate components).
Safe to re-run — uses INSERT OR IGNORE via on_conflict_do_nothing.
"""
from __future__ import annotations
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert as pg_insert
from app.database.models.resource import GameResource

RESOURCES = [
    # ── Basic synthetic ───────────────────────────────────────────────────────
    dict(code="void_dust",         name="Void Dust",              category="basic",      source="PvP/PvE",   description="Universal fine cosmic powder."),
    dict(code="astral_resin",      name="Astral Resin",           category="basic",      source="PvP/PvE",   description="Viscous binding substance for alien structures."),
    dict(code="lumen_shards",      name="Lumen Shards",           category="basic",      source="PvP",       description="Crystalline light fragments."),
    dict(code="phase_powder",      name="Phase Powder",           category="basic",      source="PvP",       description="Powder of displaced matter."),
    dict(code="gravity_silt",      name="Gravity Silt",           category="basic",      source="PvP/Boss",  description="Sediment from micro-gravity anomalies."),
    # ── Structural ───────────────────────────────────────────────────────────
    dict(code="nebula_fiber",      name="Nebula Fiber",           category="structural", source="PvP/Craft", description="Filament for armor plating."),
    dict(code="chrono_mesh",       name="Chrono Mesh",            category="structural", source="PvP/Boss",  description="Flexible weave with temporal deflection."),
    dict(code="darkweave_filament",name="Darkweave Filament",     category="structural", source="Boss",      description="Rare stealth/control set material."),
    dict(code="ionized_shell_frags",name="Ionized Shell Fragments",category="structural",source="Boss",      description="Fragments of raid-creature carapace."),
    dict(code="stellar_alloy_gel", name="Stellar Alloy Gel",      category="structural", source="Craft/Boss",description="Semi-living alloy mass for durable armor."),
    # ── Energetic ────────────────────────────────────────────────────────────
    dict(code="pulse_core",        name="Pulse Core",             category="energetic",  source="Boss",      description="Base power core for item enchantment."),
    dict(code="flux_essence",      name="Flux Essence",           category="energetic",  source="PvP/Boss",  description="Essence of energy fluctuations."),
    dict(code="quantum_condensate",name="Quantum Condensate",     category="energetic",  source="Boss",      description="Compressed high-tier energy."),
    # ── Bio ──────────────────────────────────────────────────────────────────
    dict(code="psionic_ink",       name="Psionic Ink",            category="bio",        source="Boss",      description="For willpower, control, and psychic-influence gear."),
    dict(code="bioadaptive_mucus", name="Bioadaptive Mucus",      category="bio",        source="Boss",      description="Matrix for living armor."),
    dict(code="marrow_spark",      name="Marrow Spark",           category="bio",        source="Boss",      description="Bone-core component for combat lifeforms."),
    # ── Raid-rare ────────────────────────────────────────────────────────────
    dict(code="singularity_seed",  name="Singularity Seed",       category="raid_rare",  source="Boss only", description="Very rare top-tier component."),
    dict(code="eclipse_heart",     name="Eclipse Heart",          category="raid_rare",  source="Boss only", description="Core of shadow and control sets."),
    dict(code="solar_blood",       name="Solar Blood",            category="raid_rare",  source="Boss only", description="Energy liquid for offensive sets."),
    dict(code="living_metal_spore",name="Living Metal Spore",     category="raid_rare",  source="Boss only", description="Rare self-reconfiguring material."),
    # ── Intermediate components ───────────────────────────────────────────────
    dict(code="void_binder",       name="Void Binder",            category="intermediate", source="Craft",   description="Adhesive for set components. Needs: void_dust + astral_resin."),
    dict(code="nebula_composite",  name="Nebula Composite",       category="intermediate", source="Craft",   description="Armor hull base. Needs: nebula_fiber + stellar_alloy_gel."),
    dict(code="flux_capsule",      name="Flux Capsule",           category="intermediate", source="Craft",   description="Active property fuel. Needs: flux_essence + pulse_core."),
    dict(code="psionic_seal",      name="Psionic Seal",           category="intermediate", source="Craft",   description="Will/control items. Needs: psionic_ink + chrono_mesh."),
    dict(code="adaptive_plate",    name="Adaptive Plate",         category="intermediate", source="Craft",   description="Living armor plate. Needs: ionized_shell_frags + bioadaptive_mucus."),
    dict(code="quantum_lattice",   name="Quantum Lattice",        category="intermediate", source="Craft",   description="High-tech set bonuses. Needs: quantum_condensate + chrono_mesh."),
    dict(code="eclipse_membrane",  name="Eclipse Membrane",       category="intermediate", source="Craft",   description="Stealth/control component. Needs: eclipse_heart + darkweave_filament."),
    dict(code="solar_reactor_thread",name="Solar Reactor Thread", category="intermediate", source="Craft",   description="Offensive/cast-speed bonuses. Needs: solar_blood + lumen_shards."),
    dict(code="singularity_anchor",name="Singularity Anchor",     category="intermediate", source="Craft",   description="Top-tier item core. Needs: singularity_seed + pulse_core."),
    dict(code="living_alloy_node", name="Living Alloy Node",      category="intermediate", source="Craft",   description="Self-tuning armor parts. Needs: living_metal_spore + stellar_alloy_gel."),
]


async def seed_resources(db: AsyncSession) -> int:
    inserted = 0
    for row in RESOURCES:
        stmt = (
            pg_insert(GameResource)
            .values(**row)
            .on_conflict_do_nothing(index_elements=["code"])
        )
        result = await db.execute(stmt)
        inserted += result.rowcount
    await db.commit()
    return inserted
