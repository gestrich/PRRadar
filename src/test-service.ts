// TestService - A simple service with a security issue

export class TestService {
  private db: any;

  constructor(db: any) {
    this.db = db;
  }

  // SQL Injection vulnerability - user input directly concatenated into query
  async getUserById(userId: string): Promise<any> {
    const query = "SELECT * FROM users WHERE id = '" + userId + "'";
    return this.db.query(query);
  }
}
