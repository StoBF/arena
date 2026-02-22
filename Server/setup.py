from setuptools import setup, find_packages

setup(
    name="hero_manager",
    version="0.1.0",
    packages=find_packages("app"),
    package_dir={"": "app"},
    install_requires=[
        "pydantic>=2.0",
        "pydantic-settings",
        "fastapi",
        "uvicorn[standard]",
        "sqlalchemy",
        "asyncpg",
        "python-jose",
        "passlib[bcrypt]",
        "aiosqlite",
        "slowapi",
        "python-dotenv",
        "faker",
    ],
)
