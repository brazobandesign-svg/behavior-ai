import React, { useState } from 'react';
import { Shield } from 'lucide-react';
import { supabase } from '../lib/supabase';

interface AuthModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export const AuthModal: React.FC<AuthModalProps> = ({ isOpen, onClose, onSuccess }) => {
  const [loading, setLoading] = useState(false);

  if (!isOpen) return null;

  const handleGoogleSignIn = async () => {
    setLoading(true);
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: window.location.origin,
        },
      });
      if (error) {
        console.error('Error reportado al iniciar con Google:', error);
        alert(`Error al iniciar con Google: ${error.message || error}`);
        setLoading(false);
      }
    } catch (err: any) {
      console.error('Error en catch de Google OAuth:', err);
      alert(`No se pudo iniciar sesión: ${err.message || err}`);
      setLoading(false);
    }
  };

  const handleGithubSignIn = async () => {
    setLoading(true);
    try {
      // Paridad móvil (punto 5: GitHub operativo, scope repo): OAuth real.
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'github',
        options: {
          redirectTo: window.location.origin,
          scopes: 'repo',
        },
      });
      if (error) {
        console.error('Error reportado al iniciar con GitHub:', error);
        alert(`Error al iniciar con GitHub: ${error.message || error}`);
        setLoading(false);
      }
    } catch (err: any) {
      console.error('Error en catch de GitHub OAuth:', err);
      alert(`No se pudo iniciar sesión: ${err.message || err}`);
      setLoading(false);
    }
  };

  const handleGuestSignIn = async () => {
    setLoading(true);
    try {
      // Paridad móvil (_signInAsGuest): anónimo con timeout de 2s; si cuelga,
      // se entra igual en modo invitado (la app llama continueAsGuest).
      await Promise.race([
        supabase.auth.signInAnonymously().then(({ error }) => {
          if (error) throw error;
        }),
        new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 2000)),
      ]);
    } catch (err) {
      console.warn('Acceso como invitado (timeout o fallo, se continúa igual):', err);
    } finally {
      setLoading(false);
      onSuccess();
      onClose();
    }
  };

  const handleAppleTap = () => {
    // Paridad móvil: el botón no abre nada, solo háptica sutil
    // ("Próximamente" para que no parezca roto).
    try { navigator.vibrate?.(10); } catch (_) {}
  };

  return (
    // Paridad AuthScreen móvil: pantalla completa en Negro Cálido (#0E0C0A),
    // SIN botón de cierre (el login es la puerta, no se descarta).
    <div style={{
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      backgroundColor: '#0E0C0A',
      display: 'flex',
      alignItems: 'flex-start',
      justifyContent: 'center',
      zIndex: 200,
      padding: '180px 28px 28px 28px',
      overflowY: 'auto'
    }}>
      <div style={{
        width: '100%',
        maxWidth: 360,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
      }}>
        {/* Pila de logos exacta del móvil: 96 / 60 / 40 con offset -22 */}
        <div style={{
          height: 200,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'flex-end',
          position: 'relative',
        }}>
          {/* Logo_behavior.png tintado ámbar (#C9933A) */}
          <div style={{
            width: 96,
            height: 96,
            backgroundColor: '#C9933A',
            WebkitMaskImage: 'url(/Logo_behavior.png)',
            WebkitMaskSize: 'contain',
            WebkitMaskRepeat: 'no-repeat',
            WebkitMaskPosition: 'center',
            maskImage: 'url(/Logo_behavior.png)',
            maskSize: 'contain',
            maskRepeat: 'no-repeat',
            maskPosition: 'center',
          }} />

          {/* exodo_text.png tintado yeso (#F5F2EB) */}
          <div style={{
            width: 200,
            height: 60,
            backgroundColor: '#F5F2EB',
            WebkitMaskImage: 'url(/exodo_text.png)',
            WebkitMaskSize: 'contain',
            WebkitMaskRepeat: 'no-repeat',
            WebkitMaskPosition: 'center',
            maskImage: 'url(/exodo_text.png)',
            maskSize: 'contain',
            maskRepeat: 'no-repeat',
            maskPosition: 'center'
          }} />

          {/* bybehavior_text.png tintado yeso offset -22px */}
          <div style={{
            width: 157,
            height: 40,
            backgroundColor: '#F5F2EB',
            WebkitMaskImage: 'url(/bybehavior_text.png)',
            WebkitMaskSize: 'contain',
            WebkitMaskRepeat: 'no-repeat',
            WebkitMaskPosition: 'center',
            maskImage: 'url(/bybehavior_text.png)',
            maskSize: 'contain',
            maskRepeat: 'no-repeat',
            maskPosition: 'center',
            transform: 'translateY(-22px)'
          }} />
        </div>

        <div style={{ height: 24 }} />

        {/* 1. Botón Continuar con Google (#F5F2EB píldora) */}
        <button
          type="button"
          onClick={handleGoogleSignIn}
          disabled={loading}
          style={{
            width: '100%',
            height: 54,
            borderRadius: 27,
            backgroundColor: '#F5F2EB',
            color: '#0E0C0A',
            border: 'none',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 14,
            cursor: loading ? 'wait' : 'pointer',
            boxShadow: '0 2px 10px rgba(0,0,0,0.3)',
            fontWeight: 700,
            fontSize: '16px',
            fontFamily: 'Inter, sans-serif',
            letterSpacing: '0.2px',
            transition: 'all 0.15s'
          }}
        >
          <img src="/google_logo.png" alt="Google" style={{ width: 26, height: 26 }} />
          <span>Continuar con Google</span>
        </button>

        {/* 2. Botón Continuar con Apple (paridad móvil: no abre nada, solo
            háptica sutil — "Próximamente" para que no parezca roto) */}
        <button
          type="button"
          onClick={handleAppleTap}
          disabled={loading}
          title="Próximamente"
          style={{
            width: '100%',
            height: 54,
            borderRadius: 27,
            backgroundColor: '#191919',
            color: 'rgba(245, 242, 235, 0.4)',
            border: 'none',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 14,
            cursor: loading ? 'wait' : 'pointer',
            fontWeight: 700,
            fontSize: '16px',
            fontFamily: 'Inter, sans-serif',
            letterSpacing: '0.2px',
            marginTop: 14
          }}
        >
          <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor">
            <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.35c.64-.78 1.08-1.86.96-2.94-.93.04-2.06.62-2.72 1.39-.58.67-1.1 1.77-.96 2.83 1.04.08 2.08-.5 2.72-1.28z"/>
          </svg>
          <span>Continuar con Apple</span>
        </button>

        {/* 3. Opción social GitHub — paridad móvil (operativa, scope repo) */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 20,
          marginTop: 16
        }}>
          <button
            type="button"
            onClick={handleGithubSignIn}
            disabled={loading}
            title="Continuar con GitHub"
            style={{
              width: 50,
              height: 50,
              borderRadius: 25,
              backgroundColor: '#191919',
              border: 'none',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              cursor: 'pointer'
            }}
          >
            <img src="/github_logo.png" alt="GitHub" style={{ width: 26, height: 26 }} />
          </button>
        </div>

        {/* 4. Continuar como invitado (#F5F2EB texto subrayado) */}
        <div style={{ marginTop: 24, width: '100%' }}>
          <button
            type="button"
            onClick={handleGuestSignIn}
            disabled={loading}
            style={{
              width: '100%',
              background: 'transparent',
              border: 'none',
              color: '#F5F2EB',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 8,
              cursor: loading ? 'wait' : 'pointer',
              fontFamily: 'Inter, sans-serif',
              fontSize: '14px',
              fontWeight: 500,
              textDecoration: 'underline'
            }}
          >
            <Shield size={16} />
            <span>Continuar como invitado</span>
          </button>
        </div>
      </div>
    </div>
  );
};
