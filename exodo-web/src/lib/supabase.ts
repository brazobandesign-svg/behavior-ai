import { createClient } from '@supabase/supabase-js';

const supabaseUrl = 'https://zyvaakfsnlqlgrjdigkr.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dmFha2ZzbmxxbGdyamRpZ2tyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0MDg2MTQsImV4cCI6MjA5Nzk4NDYxNH0.ZPW16OYo-09YEe-ti2DaRSh8Yh9TZEQL6e_23bvGZGU';

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});

export interface Conversation {
  id: string;
  user_id: string;
  title: string;
  model: string;
  created_at: string;
  updated_at: string;
  is_starred?: boolean;
}

export interface Message {
  id: string;
  conversation_id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  created_at: string;
  isThinking?: boolean;
}
