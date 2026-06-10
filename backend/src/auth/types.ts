export interface AuthUser {
  id: string;
  email: string;
  role: string;
}

export interface JwtPayload {
  sub: string;
  role: string;
}
