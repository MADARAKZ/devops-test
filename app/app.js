Vue.createApp({
  data: function () {
    return {
      event: { title: '', detail: '', date: '' },
      events: []
    };
  },

  mounted: function () {
    this.fetchEvents();
  },

  methods: {

    fetchEvents: function () {
      fetch('/api/events')
        .then(function (res) {
          return res.json();
        })
        .then(function (events) {
          this.events = events;
        }.bind(this))
        .catch(function (err) {
          console.error(err);
        });
    },

    addEvent: function () {
      if (this.event.title.trim()) {
        fetch('/api/events', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(this.event)
        })
          .then(function (res) {
            if (!res.ok) {
              throw new Error('Unable to add event');
            }
            return res.json();
          })
          .then(function (event) {
            this.events.push(event);
            this.event = { title: '', detail: '', date: '' };
          }.bind(this))
          .catch(function (err) {
            console.error(err);
          });
      }
    },

    deleteEvent: function (id) {
      if (confirm('Are you sure you want to delete this event?')) {
        fetch('/api/events/' + id, { method: 'DELETE' })
          .then(function (res) {
            if (!res.ok) {
              throw new Error('Unable to delete event');
            }
            var index = this.events.findIndex(function (event) {
              return event.id === id;
            });
            if (index !== -1) {
              this.events.splice(index, 1);
            }
          }.bind(this))
          .catch(function (err) {
            console.error(err);
          });
      }
    }
  }
}).mount('#events');
