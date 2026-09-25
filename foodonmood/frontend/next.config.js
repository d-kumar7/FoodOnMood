/** @type {import('next').NextEncoding} */
const nextConfig = {
  async rewrites() {
    return [
      {
        source: '/api/:path*',
        destination: process.env.INTERNAL_API_URL 
          ? `${process.env.INTERNAL_API_URL}/:path*`
          : 'http://backend:8080/:path*',
      },
    ]
  },
};

module.exports = nextConfig;
