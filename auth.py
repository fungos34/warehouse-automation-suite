from fastapi.security import OAuth2PasswordBearer, HTTPBasic, APIKeyHeader
from passlib.context import CryptContext
from fastapi import HTTPException, Depends
from datetime import datetime, timedelta
from jose import jwt, JWTError


SECRET_KEY = "773051d7-3f96-4aea-9218-2392f16c33bf"  # Use a strong random key in production!
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60

oauth2_scheme = OAuth2PasswordBearer(
    tokenUrl="/login",
    description="JWT token authentication. Use /login to get a token."
)
security = HTTPBasic()

api_key_scheme = APIKeyHeader(name="Authorization")
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def create_access_token(data: dict, expires_delta: timedelta = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def verify_token(token: str):
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise HTTPException(status_code=401, detail="Invalid token")
        return username
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")


def get_current_username(api_key: str = Depends(api_key_scheme)):
    # Accept with or without "Bearer " prefix
    if api_key.startswith("Bearer "):
        token = api_key.split(" ", 1)[1]
    else:
        token = api_key
    return verify_token(token)

