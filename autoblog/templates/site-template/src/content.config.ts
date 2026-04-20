import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const statusSchema = z.enum(['draft', 'published']).default('draft');

const timeline = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/timeline' }),
  schema: z.object({
    title: z.string(),
    date: z.coerce.date(),
    status: statusSchema,
  }),
});

const pages = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/pages' }),
  schema: z.object({
    title: z.string(),
    status: statusSchema,
  }),
});

export const collections = { timeline, pages };
