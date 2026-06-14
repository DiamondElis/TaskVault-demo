import { FormEvent, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { login } from '../api/client';
import { setToken } from '../auth/token';

export function LoginPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');

  const onSubmit = async (event: FormEvent) => {
    event.preventDefault();
    setError('');

    try {
      const response = await login(email, password);
      setToken(response.token);
      navigate('/dashboard');
    } catch {
      setError('Login failed. Check credentials.');
    }
  };

  return (
    <div className="card">
      <h1>Login</h1>
      <form onSubmit={onSubmit}>
        <label>
          Email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <label>
          Password
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>
        {error && <p className="error">{error}</p>}
        <button type="submit">Sign in</button>
      </form>
      <p>
        No account? <Link to="/register">Register</Link>
      </p>
    </div>
  );
}
