# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for MediaFlow backend.

Build with:
    cd backend
    pyinstaller mediaflow-server.spec

Output: dist/backend/mediaflow-server (+ _internal/)
"""

import os

block_cipher = None

# Collect the entire app/ package — uvicorn does string-based import
app_datas = [
    ('app', 'app'),
]

a = Analysis(
    ['run_server.py'],
    pathex=[],
    binaries=[],
    datas=app_datas,
    hiddenimports=[
        # Uvicorn internals
        'uvicorn.logging',
        'uvicorn.loops',
        'uvicorn.loops.auto',
        'uvicorn.protocols',
        'uvicorn.protocols.http',
        'uvicorn.protocols.http.auto',
        'uvicorn.protocols.websockets',
        'uvicorn.protocols.websockets.auto',
        'uvicorn.lifespan',
        'uvicorn.lifespan.on',
        'uvicorn.lifespan.off',
        # SQLAlchemy dialects
        'sqlalchemy.dialects.sqlite',
        'sqlalchemy.dialects.sqlite.aiosqlite',
        # Async DB
        'aiosqlite',
        # SSH / crypto
        'asyncssh',
        'cryptography',
        'cryptography.hazmat.primitives.kdf.pbkdf2',
        'cryptography.hazmat.primitives.ciphers.aead',
        # HTTP / networking
        'httpx',
        'httpx._transports',
        'httpx._transports.default',
        'httpcore',
        'anyio',
        'anyio._backends',
        'anyio._backends._asyncio',
        'sniffio',
        'h11',
        # FastAPI / Starlette / Pydantic
        'fastapi',
        'starlette',
        'pydantic',
        'pydantic_settings',
        'dotenv',
        # WebSockets
        'websockets',
        'websockets.legacy',
        'websockets.legacy.server',
        # Multipart / files
        'multipart',
        'aiofiles',
        # SMTP
        'aiosmtplib',
        # PDF reports
        'fpdf2',
        'fpdf',
        # Email
        'email.mime.text',
        'email.mime.multipart',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'tkinter',
        'matplotlib',
        'numpy',
        'scipy',
        'pandas',
        'PIL',
        'cv2',
        'torch',
        'tensorflow',
        'test',
        'unittest',
        'pytest',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='mediaflow-server',
    debug=False,
    bootloader_ignore_signals=False,
    strip=True,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=True,
    upx=False,
    upx_exclude=[],
    name='backend',
)
