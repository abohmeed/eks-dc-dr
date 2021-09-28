const GhostAdminAPI = require('@tryghost/admin-api');

const api = new GhostAdminAPI({
  url: process.env.URL,
  key: process.env.KEY,
  version: "v3"
});

exports.handler =  function(event, context, callback) {
  api.posts
    .browse()
    .then((posts) => {
      posts.forEach((post) => {
        api.posts.delete({id: post.id});
      });
    })
    .catch((err) => {
      return err
    });
  return null;
};
