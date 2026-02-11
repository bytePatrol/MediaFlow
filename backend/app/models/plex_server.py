from sqlalchemy import Column, Integer, String, Boolean, DateTime, func
from sqlalchemy.orm import relationship
from app.database import Base


class PlexServer(Base):
    __tablename__ = "plex_servers"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(255), nullable=False)
    url = Column(String(500), nullable=False)
    token = Column(String(500), nullable=False)
    machine_id = Column(String(255), unique=True, nullable=True)
    version = Column(String(50), nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    last_synced_at = Column(DateTime, nullable=True)

    # SSH credentials for pulling files from the NAS/Plex server
    ssh_hostname = Column(String(255), nullable=True)
    ssh_port = Column(Integer, default=22)
    ssh_username = Column(String(100), nullable=True)
    ssh_key_path = Column(String(500), nullable=True)
    ssh_password = Column(String(500), nullable=True)
    benchmark_path = Column(String(500), nullable=True)

    libraries = relationship("PlexLibrary", back_populates="server", cascade="all, delete-orphan")
