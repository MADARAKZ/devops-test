var events = require('./events.js');

exports.events = function (req, res) {
  res.json(events);
};

exports.event = function (req, res) {
  if (req.method === 'POST') {
    if (!req.body || !req.body.title) {
      return res.status(400).json({ error: 'Event title is required' });
    }

    var nextId = events.reduce(function (maxId, event) {
      return Math.max(maxId, event.id);
    }, 0) + 1;

    var event = {
      id: nextId,
      title: req.body.title,
      detail: req.body.detail || '',
      date: req.body.date || ''
    };

    events.push(event);
    return res.status(201).json(event);
  }

  var eventId = Number(req.params.eventId);
  var eventIndex = events.findIndex(function (event) {
    return event.id === eventId;
  });

  if (eventIndex === -1) {
    return res.status(404).json({ error: 'Event not found' });
  }

  var removed = events.splice(eventIndex, 1)[0];
  res.json(removed);
};
