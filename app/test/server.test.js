const request = require('supertest');

const app = require('../server');

describe('bulletin board app', () => {
  test('GET / renders the bulletin board page', async () => {
    const response = await request(app).get('/');

    expect(response.status).toBe(200);
    expect(response.text).toContain('Welcome to the Bulletin Board');
  });

  test('GET /health returns application health', async () => {
    const response = await request(app).get('/health');

    expect(response.status).toBe(200);
    expect(response.body).toEqual({ status: 'ok' });
  });

  test('GET /api/events returns the seeded events', async () => {
    const response = await request(app).get('/api/events');

    expect(response.status).toBe(200);
    expect(response.body).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          id: 1,
          title: 'Docker Workshop'
        })
      ])
    );
  });

  test('POST /api/events creates a new event', async () => {
    const response = await request(app)
      .post('/api/events')
      .send({
        title: 'Kubernetes Workshop',
        detail: 'Hands-on deployment session',
        date: '2026-05-23'
      });

    expect(response.status).toBe(201);
    expect(response.body).toEqual(
      expect.objectContaining({
        id: expect.any(Number),
        title: 'Kubernetes Workshop',
        detail: 'Hands-on deployment session',
        date: '2026-05-23'
      })
    );
  });

  test('POST /api/events rejects missing title', async () => {
    const response = await request(app)
      .post('/api/events')
      .send({ detail: 'Missing title' });

    expect(response.status).toBe(400);
    expect(response.body.error).toBe('Event title is required');
  });

  test('DELETE /api/events/:eventId deletes an event', async () => {
    const createResponse = await request(app)
      .post('/api/events')
      .send({ title: 'Temporary Event' });

    const deleteResponse = await request(app).delete(
      `/api/events/${createResponse.body.id}`
    );

    expect(deleteResponse.status).toBe(200);
    expect(deleteResponse.body.title).toBe('Temporary Event');
  });

  test('DELETE /api/events/:eventId returns 404 when event does not exist', async () => {
    const response = await request(app).delete('/api/events/99999');

    expect(response.status).toBe(404);
    expect(response.body.error).toBe('Event not found');
  });
});
