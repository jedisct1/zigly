// Parallel Requests Example
// Fans out to several backends at once and streams the responses back
// in completion order instead of waiting for them one by one

const zigly = @import("zigly");
const Request = zigly.http.Request;
const PendingRequest = zigly.http.PendingRequest;

pub fn main() !void {
    const downstream = try zigly.downstream();

    // Start all requests without waiting for any response
    var users = try Request.new("GET", "https://api.example.com/users");
    var orders = try Request.new("GET", "https://api.example.com/orders");
    var stats = try Request.new("GET", "https://api.example.com/stats");

    var pending = [_]PendingRequest{
        try users.sendAsync("api_backend"),
        try orders.sendAsync("api_backend"),
        try stats.sendAsync("api_backend"),
    };

    // Stream each response back as it arrives; total time is the slowest
    // request, not the sum of all of them
    var response = downstream.response;
    try response.setStatus(200);
    try response.flush();

    var responses = PendingRequest.iterator(&pending);
    while (try responses.next()) |upstream| {
        try response.body.append(upstream.body);
        try response.body.writeAll("\n");
    }
    try response.body.close();
}
