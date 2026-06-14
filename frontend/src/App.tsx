import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { Layout } from './components/Layout';
import { ProtectedRoute } from './components/ProtectedRoute';
import { AdminPage } from './pages/Admin';
import { DashboardPage } from './pages/Dashboard';
import { FilesPage } from './pages/Files';
import { HealthPage } from './pages/Health';
import { LoginPage } from './pages/Login';
import { RegisterPage } from './pages/Register';
import { TasksPage } from './pages/Tasks';

export function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<Layout />}>
          <Route path="/" element={<Navigate to="/dashboard" replace />} />
          <Route path="/login" element={<LoginPage />} />
          <Route path="/register" element={<RegisterPage />} />
          <Route path="/health" element={<HealthPage />} />
          <Route element={<ProtectedRoute />}>
            <Route path="/dashboard" element={<DashboardPage />} />
            <Route path="/tasks" element={<TasksPage />} />
            <Route path="/files" element={<FilesPage />} />
            <Route path="/admin" element={<AdminPage />} />
          </Route>
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
