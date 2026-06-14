import { Link, Outlet, useNavigate } from 'react-router-dom';
import { useEffect, useState } from 'react';
import { getMe } from '../api/client';
import type { User } from '../api/types';
import { clearToken, getToken } from '../auth/token';

export function Layout() {
  const navigate = useNavigate();
  const [user, setUser] = useState<User | null>(null);

  useEffect(() => {
    if (!getToken()) {
      return;
    }

    getMe()
      .then(setUser)
      .catch(() => setUser(null));
  }, []);

  const logout = () => {
    clearToken();
    navigate('/login');
  };

  return (
    <div className="layout">
      <nav>
        <Link to="/dashboard">Dashboard</Link>
        <Link to="/tasks">Tasks</Link>
        <Link to="/files">Files</Link>
        {user?.role === 'admin' && <Link to="/admin">Admin</Link>}
        <Link to="/health">Health</Link>
        {user ? (
          <button type="button" className="secondary" onClick={logout}>
            Logout ({user.email})
          </button>
        ) : (
          <>
            <Link to="/login">Login</Link>
            <Link to="/register">Register</Link>
          </>
        )}
      </nav>
      <Outlet />
    </div>
  );
}
