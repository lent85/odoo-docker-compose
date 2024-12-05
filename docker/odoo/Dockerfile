FROM odoo:18.0

USER root

# Copy custom entrypoint script
COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

# Create requirements.txt file
RUN echo "# Add your Python dependencies here" > /etc/odoo/requirements.txt

# Switch back to odoo user
USER odoo

ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]
