/**
 * The Claude adapter, against a stubbed SDK client: what it sends, and how it reads answers.
 */
import { describe, expect, it, vi } from 'vitest';
import { claudeModerationModel, MODERATION_MODEL_ID } from '@/server/moderation/claude';
import { ModelRefusal } from '@/server/moderation/model';

type ParseArgs = [Record<string, unknown>, { signal?: AbortSignal }?];

function stubClient(reply: Record<string, unknown>) {
  const parse = vi.fn(async (..._args: ParseArgs) => reply);
  const client = { messages: { parse } } as unknown as Parameters<typeof claudeModerationModel>[1];
  return { parse, client };
}

const signal = new AbortController().signal;

describe('claudeModerationModel', () => {
  it('asks claude-haiku-5-5 for strict JSON about the photo, fast', async () => {
    const { parse, client } = stubClient({
      stop_reason: 'end_turn',
      parsed_output: {
        person_present: true,
        face_visible: true,
        nudity: false,
        outfit_visible: true,
        possibly_under_18: false,
      },
    });
    const model = claudeModerationModel('sk-ant-test', client);
    const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
    const findings = await model.classifyImage({ kind: 'card', original: jpeg, jpeg, signal });

    expect(findings).toEqual({
      personPresent: true,
      faceVisible: true,
      nudity: false,
      outfitVisible: true,
      possiblyUnder18: false,
    });
    const [params, options] = parse.mock.calls[0]!;
    expect(params.model).toBe(MODERATION_MODEL_ID);
    expect(MODERATION_MODEL_ID).toBe('claude-haiku-5-5');
    expect(params.thinking).toEqual({ type: 'disabled' });
    expect(params).not.toHaveProperty('temperature');
    const output = params.output_config as { effort: string; format: { type: string } };
    expect(output.effort).toBe('low');
    expect(output.format.type).toBe('json_schema');
    const content = (params.messages as { content: { type: string; source?: unknown }[] }[])[0]!
      .content;
    expect(content[0]).toEqual({
      type: 'image',
      source: { type: 'base64', media_type: 'image/jpeg', data: '/9j/2Q==' },
    });
    expect(options?.signal).toBe(signal);
  });

  it('wraps chat text in tags and reads the verdict', async () => {
    const { parse, client } = stubClient({
      stop_reason: 'end_turn',
      parsed_output: { flagged: true, category: 'threat' },
    });
    const model = claudeModerationModel('sk-ant-test', client);
    await expect(model.classifyText({ body: 'hello', signal })).resolves.toEqual({
      flagged: true,
      category: 'threat',
    });
    const [params] = parse.mock.calls[0]!;
    expect(params.messages).toEqual([{ role: 'user', content: '<message>\nhello\n</message>' }]);
  });

  it('never flags with category none', async () => {
    const { client } = stubClient({
      stop_reason: 'end_turn',
      parsed_output: { flagged: true, category: 'none' },
    });
    const model = claudeModerationModel('sk-ant-test', client);
    await expect(model.classifyText({ body: 'x', signal })).resolves.toEqual({
      flagged: false,
      category: 'none',
    });
  });

  it('reports refusals and answers that miss the schema', async () => {
    const refused = claudeModerationModel(
      'k',
      stubClient({ stop_reason: 'refusal', parsed_output: null }).client,
    );
    await expect(refused.classifyText({ body: 'x', signal })).rejects.toBeInstanceOf(ModelRefusal);
    const garbled = claudeModerationModel(
      'k',
      stubClient({ stop_reason: 'end_turn', parsed_output: null }).client,
    );
    const jpeg = new Uint8Array([0xff, 0xd8]);
    await expect(
      garbled.classifyImage({ kind: 'profile', original: jpeg, jpeg, signal }),
    ).rejects.toThrow(/schema/);
  });
});
