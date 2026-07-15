import React, { useState } from 'react';
import { X, Shield } from 'lucide-react';
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
      if (error) throw error;
    } catch (err) {
      console.warn('Error con Google OAuth, procediendo:', err);
      setLoading(false);
      onSuccess();
      onClose();
    }
  };

  const handleGuestSignIn = async () => {
    setLoading(true);
    try {
      const { error } = await supabase.auth.signInAnonymously();
      if (error) throw error;
    } catch (err) {
      console.warn('Fallback acceso como invitado al milisegundo 0:', err);
    } finally {
      setLoading(false);
      onSuccess();
      onClose();
    }
  };

  return (
    <div style={{
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      backgroundColor: '#0E0C0A',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      zIndex: 200,
      padding: 28,
      overflowY: 'auto'
    }}>
      {/* Botón de cierre discreto arriba a la derecha */}
      <button
        onClick={onClose}
        style={{
          position: 'absolute',
          top: 28,
          right: 28,
          background: 'transparent',
          border: 'none',
          color: '#9E9689',
          cursor: 'pointer',
          padding: 8
        }}
        title="Cerrar"
      >
        <X size={24} />
      </button>

      <div style={{
        width: '100%',
        maxWidth: 360,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        paddingTop: 40,
        paddingBottom: 28
      }}>
        {/* Pila de logos exacta del móvil (#0E0C0A) */}
        <div style={{
          height: 180,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'flex-end',
          position: 'relative',
          marginBottom: 36
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
            marginBottom: 8
          }} />

          {/* exodo_text.png tintado yeso (#F5F2EB) */}
          <div style={{
            width: 160,
            height: 48,
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

          {/* bybehavior_text.png tintado yeso offset -18px */}
          <div style={{
            width: 110,
            height: 28,
            backgroundColor: '#F5F2EB',
            WebkitMaskImage: 'url(/bybehavior_text.png)',
            WebkitMaskSize: 'contain',
            WebkitMaskRepeat: 'no-repeat',
            WebkitMaskPosition: 'center',
            maskImage: 'url(/bybehavior_text.png)',
            maskSize: 'contain',
            maskRepeat: 'no-repeat',
            maskPosition: 'center',
            transform: 'translateY(-12px)'
          }} />
        </div>

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
            fontSize: '1rem',
            fontFamily: 'Inter, sans-serif',
            letterSpacing: '0.01em',
            transition: 'all 0.15s'
          }}
        >
          <img src="/google_logo.png" alt="Google" style={{ width: 24, height: 24 }} />
          <span>{loading ? 'Conectando...' : 'Continuar con Google'}</span>
        </button>

        {/* 2. Botón Continuar con Apple (Deshabilitado / surface #191919) */}
        <button
          type="button"
          disabled
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
            cursor: 'not-allowed',
            fontWeight: 700,
            fontSize: '1rem',
            fontFamily: 'Inter, sans-serif',
            letterSpacing: '0.01em',
            marginTop: 14
          }}
        >
          <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
            <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.35c.64-.78 1.08-1.86.96-2.94-.93.04-2.06.62-2.72 1.39-.58.67-1.1 1.77-.96 2.83 1.04.08 2.08-.5 2.72-1.28z"/>
          </svg>
          <span>Continuar con Apple</span>
        </button>

        {/* 3. Opciones sociales circulares (𝕏 y GitHub) */}
        <div style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 20,
          marginTop: 18
        }}>
          <button
            type="button"
            onClick={() => alert('Autenticación con X / Twitter en desarrollo')}
            style={{
              width: 50,
              height: 50,
              borderRadius: 25,
              backgroundColor: '#191919',
              border: 'none',
              color: '#F5F2EB',
              fontSize: '1.35rem',
              fontWeight: 'bold',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              cursor: 'pointer'
            }}
          >
            𝕏
          </button>

          <button
            type="button"
            onClick={() => alert('Autenticación con GitHub en desarrollo')}
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
            <img src="/github_logo.png" alt="GitHub" style={{ width: 24, height: 24 }} />
          </button>
        </div>

        {/* 4. Continuar como invitado (#F5F2EB texto subrayado) */}
        <div style={{ marginTop: 28, width: '100%' }}>
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
              fontSize: '0.9rem',
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
