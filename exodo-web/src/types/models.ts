export interface ModelOption {
  id: string;
  modelId: string;
  title: string;
  subtitle: string;
  plan: 'genesis' | 'hazak';
  description: string;
  descriptionEn: string;
}

export const EXODO_MODELS: ModelOption[] = [
  {
    id: 'g11',
    modelId: 'gpt-4o-mini',
    title: 'G1.1',
    subtitle: 'Genesis',
    plan: 'genesis',
    description: 'Modelo capaz para tareas diarias.',
    descriptionEn: 'Capable model for everyday tasks.',
  },
  {
    id: 'xpi',
    modelId: 'deepseek-chat',
    title: 'XPi',
    subtitle: '',
    plan: 'hazak',
    description: 'Razonamiento avanzado para tareas exigentes.',
    descriptionEn: 'Advanced reasoning for demanding tasks.',
  },
];
