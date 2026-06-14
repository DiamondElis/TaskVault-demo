import { FormEvent, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { register } from '../api/client';
import { setToken } from '../auth/token';

export function RegisterPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');

  const onSubmit = async (event: FormEvent) => {
    event.preventDefault();
    setError('');

    try {
      const response = await register(email, password);
      setToken(response.token);
      navigate('/dashboard');
    } catch {
      setError('Registration failed. Email may already exist or password too short.');
    }
  };

  return (
    <div className="card">
      <h1>Register</h1>
      <form onSubmit={onSubmit}>
        <label>
          Email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <label>
          Password (min 8 chars)
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            minLength={8}
            required
          />
        </label>
        {error && <p className="error">{error}</p>}
        <button type="submit">Create account</button>
      </form>
      <p>
        Already registered? <Link to="/login">Login</Link>
      </p>
    </div>
  );
}
