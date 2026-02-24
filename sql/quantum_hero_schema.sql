-- Schema for sci-fi quantum hero game

-- 1. heroes table
CREATE TABLE heroes (
    id SERIAL PRIMARY KEY,
    name TEXT,
    level INT,
    quantum_crafting_skill INT
);

-- 2. equipment table
CREATE TABLE equipment (
    id SERIAL PRIMARY KEY,
    hero_id INT REFERENCES heroes(id),
    slot TEXT CHECK (slot IN ('Helmet','Armor','Gloves','Boots','Quantum Module')),
    stability INT,
    energy INT,
    durability INT,
    mutation_chance FLOAT
);

-- 3. resources table
CREATE TABLE resources (
    id SERIAL PRIMARY KEY,
    name TEXT CHECK (name IN ('Quantum Dust','Cosmic Alloy','Photon Shard','Nano Gel')),
    quantity INT
);

-- 4. recipes table
CREATE TABLE recipes (
    id SERIAL PRIMARY KEY,
    output_slot TEXT CHECK (output_slot IN ('Helmet','Armor','Gloves','Boots','Quantum Module')),
    required_resources JSON,
    mutation_chance FLOAT
);

-- 5. crafted_items table
CREATE TABLE crafted_items (
    id SERIAL PRIMARY KEY,
    hero_id INT REFERENCES heroes(id),
    equipment_id INT REFERENCES equipment(id),
    created_at TIMESTAMP DEFAULT NOW()
);
