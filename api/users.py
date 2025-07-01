from fastapi import APIRouter, HTTPException, Depends
from database import get_conn
from models import LoginRequest
from auth import create_access_token, get_current_username
from passlib.context import CryptContext
from datetime import timedelta
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
from auth import ACCESS_TOKEN_EXPIRE_MINUTES


router = APIRouter()


@router.post("/users/", tags=["User"])
def create_user(username: str, password: str, partner_id: int = None, company_id: int = None):
    password_hash = pwd_context.hash(password)
    with get_conn() as conn:
        # Check if username already exists
        existing = conn.execute("SELECT id FROM user WHERE username = ?", (username,)).fetchone()
        if existing:
            raise HTTPException(status_code=400, detail="Username already exists")
        conn.execute(
            "INSERT INTO user (username, password_hash, partner_id, company_id) VALUES (?, ?, ?, ?)",
            (username, password_hash, partner_id, company_id)
        )
        conn.commit()
    return {"message": "User created"}

@router.post("/login", tags=["User"])
def login(data: LoginRequest):
    username = data.username
    password = data.password
    with get_conn() as conn:
        user = conn.execute(
            "SELECT * FROM user WHERE username = ?", (username,)
        ).fetchone()
        if not user or not pwd_context.verify(password, user["password_hash"]):
            raise HTTPException(status_code=401, detail="Incorrect username or password")
    access_token = create_access_token(
        data={"sub": username},
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    return {"access_token": access_token, "token_type": "bearer"}

@router.post("/logout", tags=["User"])
def logout(username: str = Depends(get_current_username)):
    # Instruct client to clear credentials (stateless)
    return {"message": f"Bye {username}! Please clear your credentials in your browser or client."}

